$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $env:MURAL_KUBECONFIG) {
  throw "Kubeconfig exclusivo ja existe; nao sobrescrever arquivo fora deste estado: $env:MURAL_KUBECONFIG"
}

$clusters = & kind get clusters
if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel consultar clusters kind' }
if ($clusters -contains $env:MURAL_CLUSTER) { throw "Nome de cluster ja utilizado fora deste estado: $env:MURAL_CLUSTER" }

$contexts = & kubectl config get-contexts -o name
if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel consultar os contextos locais' }
if ($contexts -contains ('kind-' + $env:MURAL_CLUSTER)) { throw "Contexto global ja existente; escolha outro cluster_name: kind-$env:MURAL_CLUSTER" }
