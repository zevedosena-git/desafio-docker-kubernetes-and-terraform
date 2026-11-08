locals {
  repo_root       = abspath("${path.module}/../..")
  chart_path      = abspath("${path.module}/../helm/mural")
  kubeconfig_path = abspath("${path.module}/.mural-${var.cluster_name}.kubeconfig")
  platform        = "linux/amd64"
  source_files = {
    api = concat(["app/docker/api.Dockerfile", "app/api/go.mod", "app/api/go.sum"], [for f in sort(tolist(fileset(local.repo_root, "app/api/*.go"))) : f])
    web = concat(["app/docker/web.Dockerfile"], sort(tolist(fileset(local.repo_root, "app/web/*"))))
  }
  source_hashes = {
    for component, paths in local.source_files : component => sha256(jsonencode({
      platform = local.platform
      files    = { for p in paths : p => filesha256("${local.repo_root}/${p}") }
    }))
  }
  image_repositories = { for component in keys(local.source_files) : component => "mural-${var.cluster_name}-${component}" }
  image_tags         = { for component, digest in local.source_hashes : component => substr(digest, 0, 16) }
  chart_hash         = sha256(jsonencode({ for f in sort(tolist(fileset(local.chart_path, "**"))) : f => filesha256("${local.chart_path}/${f}") }))
}

# Criado antes do cluster: no destroy, a limpeza do arquivo ocorre depois dele.
resource "terraform_data" "kubeconfig" {
  input = {
    path    = local.kubeconfig_path
    cluster = var.cluster_name
  }
  triggers_replace = [local.kubeconfig_path]

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-Command"]
    environment = {
      MURAL_KUBECONFIG = self.input.path
      MURAL_CLUSTER    = self.input.cluster
    }
    command = <<-PS
      $ErrorActionPreference = 'Stop'
      if (Test-Path -LiteralPath $env:MURAL_KUBECONFIG) { throw 'Kubeconfig exclusivo já existe; não sobrescrever arquivo fora deste estado.' }
      $clusters = & kind get clusters
      if ($LASTEXITCODE -ne 0) { throw 'Não foi possível consultar clusters kind' }
      if ($clusters -contains $env:MURAL_CLUSTER) { throw 'Nome de cluster já utilizado fora deste estado' }
      $contexts = & kubectl config get-contexts -o name
      if ($LASTEXITCODE -ne 0) { throw 'Não foi possível consultar os contextos locais' }
      if ($contexts -contains ('kind-' + $env:MURAL_CLUSTER)) { throw 'Contexto global já existente; escolha outro cluster_name' }
    PS
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-Command"]
    environment = { MURAL_KUBECONFIG = self.input.path }
    command     = "if (Test-Path -LiteralPath $env:MURAL_KUBECONFIG) { Remove-Item -LiteralPath $env:MURAL_KUBECONFIG -ErrorAction Stop }"
  }
}

resource "kind_cluster" "mural" {
  name            = var.cluster_name
  node_image      = "kindest/node:v1.32.2"
  wait_for_ready  = true
  kubeconfig_path = local.kubeconfig_path
  depends_on      = [terraform_data.kubeconfig]

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    node {
      role = "control-plane"
      kubeadm_config_patches = [<<-YAML
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
      YAML
      ]
      extra_port_mappings {
        container_port = 80
        host_port      = var.http_port
        listen_address = "127.0.0.1"
      }
      extra_port_mappings {
        container_port = 443
        host_port      = var.https_port
        listen_address = "127.0.0.1"
      }
    }
  }
}

provider "kind" {}

provider "kubernetes" {
  host                   = kind_cluster.mural.endpoint
  client_certificate     = kind_cluster.mural.client_certificate
  client_key             = kind_cluster.mural.client_key
  cluster_ca_certificate = kind_cluster.mural.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.mural.endpoint
    client_certificate     = kind_cluster.mural.client_certificate
    client_key             = kind_cluster.mural.client_key
    cluster_ca_certificate = kind_cluster.mural.cluster_ca_certificate
  }
}

resource "kubernetes_namespace_v1" "mural" {
  metadata { name = "mural" }
}

resource "kubernetes_namespace_v1" "traefik" {
  metadata { name = "traefik" }
}

resource "terraform_data" "images" {
  for_each = local.source_files
  input = {
    image      = "${local.image_repositories[each.key]}:${local.image_tags[each.key]}"
    dockerfile = "${local.repo_root}/app/docker/${each.key}.Dockerfile"
    repo_root  = local.repo_root
    platform   = local.platform
    cluster    = kind_cluster.mural.name
  }
  triggers_replace = [local.source_hashes[each.key], sha256(kind_cluster.mural.kubeconfig)]

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-Command"]
    environment = {
      MURAL_IMAGE      = self.input.image
      MURAL_DOCKERFILE = self.input.dockerfile
      MURAL_REPO_ROOT  = self.input.repo_root
      MURAL_PLATFORM   = self.input.platform
      MURAL_CLUSTER    = self.input.cluster
    }
    command = <<-PS
      $ErrorActionPreference = 'Stop'
      & docker build --platform $env:MURAL_PLATFORM -f $env:MURAL_DOCKERFILE -t $env:MURAL_IMAGE $env:MURAL_REPO_ROOT
      if ($LASTEXITCODE -ne 0) { throw 'Build da imagem falhou' }
      & kind load docker-image $env:MURAL_IMAGE --name $env:MURAL_CLUSTER
      if ($LASTEXITCODE -ne 0) { throw 'Carregamento da imagem no kind falhou' }
    PS
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-Command"]
    environment = { MURAL_IMAGE = self.input.image }
    command     = <<-PS
      $ErrorActionPreference = 'Stop'
      $imageId = & docker image ls --quiet $env:MURAL_IMAGE
      if ($LASTEXITCODE -ne 0) { throw 'Consulta da tag gerenciada falhou' }
      if ($imageId) {
        & docker image rm $env:MURAL_IMAGE
        if ($LASTEXITCODE -ne 0) { throw 'Remoção da tag gerenciada falhou' }
      }
    PS
  }
}

resource "helm_release" "traefik" {
  name            = "traefik"
  repository      = "https://traefik.github.io/charts"
  chart           = "traefik"
  version         = "34.4.1"
  namespace       = kubernetes_namespace_v1.traefik.metadata[0].name
  wait            = true
  wait_for_jobs   = true
  timeout         = 600
  atomic          = true
  cleanup_on_fail = true
  values = [yamlencode({
    deployment   = { replicas = 1 }
    service      = { type = "ClusterIP" }
    providers    = { kubernetesCRD = { enabled = false }, kubernetesIngress = { enabled = true, publishedService = { enabled = false } } }
    ingressClass = { enabled = true, isDefaultClass = false, name = "traefik" }
    nodeSelector = { "ingress-ready" = "true" }
    tolerations  = [{ key = "node-role.kubernetes.io/control-plane", operator = "Exists", effect = "NoSchedule" }]
    ports = {
      web       = { port = 8000, hostPort = 80 }
      websecure = { port = 8443, hostPort = 443 }
    }
    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { cpu = "500m", memory = "256Mi" }
    }
  })]
}

resource "helm_release" "mural" {
  name            = "mural"
  chart           = local.chart_path
  namespace       = kubernetes_namespace_v1.mural.metadata[0].name
  description     = "Mural chart sha256:${local.chart_hash}"
  wait            = true
  wait_for_jobs   = true
  timeout         = 600
  atomic          = true
  cleanup_on_fail = true
  depends_on      = [terraform_data.images, helm_release.traefik]

  values = [yamlencode({
    api     = { image = { repository = local.image_repositories.api, tag = local.image_tags.api, pullPolicy = "IfNotPresent" } }
    web     = { image = { repository = local.image_repositories.web, tag = local.image_tags.web, pullPolicy = "IfNotPresent" } }
    ingress = { host = var.host, className = "traefik" }
  }), yamlencode({ postgres = { password = var.postgres_password } })]
}
