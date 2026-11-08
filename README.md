# Mural de Recados: do compose ao cluster

Infraestrutura do Mural de Recados (front nginx, API Go e Postgres) num cluster **kind**, provisionado e implantado só pelo **Terraform**. Um `terraform apply` cria tudo, um segundo `apply` não muda nada e um `terraform destroy` remove tudo. O código da aplicação (`app/api`, `app/web`) não foi alterado.

```
app/docker/          api.Dockerfile (multi-stage → scratch) e web.Dockerfile (nginx)
infra/helm/mural/    chart: API, web, Postgres (StatefulSet + PVC), Ingress, Secret, ConfigMaps, Job de migração
infra/terraform/     maestro: cluster kind, build + kind load, Traefik, release do chart
docker-compose.yml   ambiente de entendimento com imagens oficiais (não é a entrega)
```

## Pré-requisitos

Docker, kind, kubectl, Helm e Terraform `>= 1.5` no PATH, com as portas 80 e 443 livres. Funciona em Linux, macOS (Intel ou Apple Silicon) e Windows: o Terraform detecta o sistema e usa `infra/terraform/scripts/*.sh` ou `*.ps1`. As imagens são construídas na arquitetura nativa do Docker, a mesma do nó kind.

## Subir no cluster

A senha do Postgres vem de `TF_VAR_postgres_password` no `.env`, que é ignorado pelo Git. Crie o arquivo a partir do modelo e preencha a senha:

```sh
cp .env.example .env
```

Use a mesma senha em todos os `apply` e no `destroy`: o Postgres só lê a senha na primeira inicialização do volume.

Linux/macOS (o `make` carrega o `.env`):

```sh
make up          # terraform init + apply
make up          # segundo apply: 0 added, 0 changed, 0 destroyed
make status      # pods, job, pvc e ingress no namespace mural
make down        # terraform destroy
```

Windows (PowerShell), carregando o `.env` na sessão antes:

```powershell
Get-Content .env | Where-Object { $_ -match '^\s*([^#=\s]+)\s*=(.*)$' } | ForEach-Object { Set-Item "env:$($Matches[1])" $Matches[2].Trim() }
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform apply
terraform -chdir=infra/terraform apply      # 0 added, 0 changed, 0 destroyed
terraform -chdir=infra/terraform destroy
```

Abra <http://mural.localtest.me> (resolve para 127.0.0.1, sem editar o arquivo hosts). O kubeconfig do cluster fica num arquivo exclusivo, que é apagado no `destroy`:

```sh
kubectl --kubeconfig "$(terraform -chdir=infra/terraform output -raw kubeconfig_path)" -n mural get pods
```

O host e as portas podem ser trocados antes do primeiro `apply` com `TF_VAR_host`, `TF_VAR_http_port` e `TF_VAR_https_port`.

## Teste do ciclo em Linux via contêiner

Roda `apply` → `apply` → `destroy` num toolbox Linux (Terraform, kind, kubectl e cliente Docker), usando o Docker do host pelo socket. Funciona inclusive a partir do Windows com Docker Desktop. O teste usa uma cópia isolada do repositório, sem tocar no state local. Ele confere o front e a API pelo Ingress, exige 0/0/0 no segundo `apply` e faz `destroy` mesmo se algo falhar. As portas 80 e 443 precisam estar livres.

```sh
make test-linux
```

Sem `make` (PowerShell):

```powershell
docker build -f infra/test/toolbox.Dockerfile -t mural-toolbox:local infra/test
docker run --rm --network host -v /var/run/docker.sock:/var/run/docker.sock -v "${PWD}:/src:ro" --env-file .env mural-toolbox:local sh /src/infra/test/linux-cycle.sh
```

## Compose local (só para entender a app)

```sh
cp .env.example .env    # preencha POSTGRES_PASSWORD
docker compose up       # db → migrate → api → web
# http://localhost:8080
docker compose down --volumes
```

A `DATABASE_URL` da API é montada a partir de `POSTGRES_*`. Se a senha tiver caracteres reservados de URL, defina também `DATABASE_URL` no `.env`, com a senha codificada (percent-encoding).

## Imagem da API: antes e depois

| Imagem | Tamanho |
|---|---|
| `golang:1.23-alpine` (como o compose roda a API, com `go run`) | 246,1 MB |
| `api.Dockerfile` final (`scratch`, binário estático) | **9,4 MB** (−96%) |

Medido em linux/amd64 com `docker image inspect --format '{{.Size}}'`. A imagem final tem apenas o binário compilado com `CGO_ENABLED=0 -trimpath -ldflags="-s -w"` e roda como usuário não-root (65532). O front tem 48 MB (nginx:1.27-alpine com os estáticos).

## Decisões

- **Migração como Job comum, não hook.** Um hook `pre-install` rodaria antes de o Postgres existir. Como Job da release, ele roda junto do StatefulSet, espera o banco por tempo limitado e aplica todos os `files/migrations/*.sql`, em ordem e numa transação única. A API sobe em paralelo, mas só fica Ready quando `/readyz` encontra a tabela. O nome do Job deriva do hash da especificação e das migrations, então só roda de novo quando algo muda, e o `wait_for_jobs` faz o `apply` aguardar a conclusão.
- **Probes.** Na API, liveness em `/healthz` (não toca no banco) e readiness em `/readyz`. Com o banco fora do ar, a API fica NotReady sem reiniciar. O Postgres usa `pg_isready` com startupProbe.
- **Secret.** `values.yaml` não tem senha e nenhum arquivo versionado define uma. O Terraform injeta `postgres.password` (variável `sensitive`, vinda do `.env`) e o chart gera o Secret com `POSTGRES_PASSWORD` e a `DATABASE_URL` codificada, consumidos via `secretKeyRef`. O chart falha se a senha não for informada. O state do Terraform e os metadados do Helm guardam a senha, e por isso o state é ignorado pelo Git.
- **Persistência.** StatefulSet com `volumeClaimTemplates` na StorageClass padrão do kind e `PGDATA` num subdiretório do volume. Os dados sobrevivem à recriação do pod.
- **Idempotência.** As tags das imagens vêm do hash dos Dockerfiles e fontes, e o build/load (`terraform_data`) só roda quando esse hash ou o cluster mudam. A `description` da release leva o hash do chart, para o provider Helm detectar mudanças num chart local. Sem timestamps nem valores voláteis.
- **Destroy limpo.** Remove releases, namespaces, o cluster, as tags de imagem criadas e o kubeconfig exclusivo. Não faz prune global nem mexe em imagens base ou no kubeconfig do usuário. Antes de criar, um preflight recusa um cluster ou contexto kind com o mesmo nome.
- **Traefik** (chart 34.4.1) com `hostPort` 80/443 no nó com label `ingress-ready=true`. O Ingress manda `/api` para a API e `/` para o front, que também faz proxy de `/api` via `API_UPSTREAM`.
- **Providers fixados**: kind 0.11.0, Helm 2.14.1, Kubernetes 2.36.0. O `.terraform.lock.hcl` versionado tem hashes para Windows, Linux e macOS.
- **Requests/limits** em todos os contêineres: API, web, Postgres, Job e Traefik.

## Problemas de ambiente conhecidos

- **`Failed to load plugin schemas` com `x509: certificate signed by unknown authority`**: um antivírus com inspeção de HTTPS (por exemplo, o Escudo da Web do Norton) intercepta o TLS local entre o Terraform e os plugins. Desative a inspeção de HTTPS ou o antivírus.
- **`connection was forcibly closed` ao baixar o chart do Traefik**: em algumas redes, o IPv6 para a CDN do GitHub (`2606:50c0::/32`) falha. No Windows, priorize IPv4 com `netsh interface ipv6 set prefixpolicy ::ffff:0:0/96 60 4` (como administrador). Para reverter: `netsh interface ipv6 set prefixpolicy ::ffff:0:0/96 35 4`.

## Fora do escopo

HPA e teste de carga (bônus) não foram implementados. A rotação de senha de um banco já inicializado também não faz parte do fluxo: o Postgres só lê `POSTGRES_PASSWORD` na primeira inicialização do volume.
