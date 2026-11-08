# Mural de Recados — infraestrutura local

Compose, Dockerfiles, chart Helm e Terraform para o núcleo obrigatório de `task_mba.md`. API, front e migrations originais preservados. Sem HPA, carga ou automações de bônus.

**15/15 critérios de aceite aprovados em 07/11/2026.** O ciclo limpo `final-20261107-150712` criou 8 recursos em um único apply, validou navegador, probes e persistência, confirmou o segundo apply sem alterações e removeu os 8 recursos no destroy, preservando os recursos externos.

## Pré-requisitos

Windows/PowerShell, Docker Desktop Linux, Compose, kind, kubectl, Helm e Terraform no PATH; portas 8080 (Compose) e 80/443 (kind) livres. É necessário acesso aos downloads de imagens, providers, Traefik e módulos Go. O navegador precisa acessar `esm.sh`, utilizado pelo front original.

Versões observadas em 07/11/2026: Docker Engine 29.7.2 / Desktop 4.86.0, Compose 5.3.1, PowerShell 7.6.9, kind 0.27.0, Helm 3.17.3 e Terraform 1.13.5. O kubectl do host é 1.36.1; prefira 1.32.x para o nó Kubernetes 1.32.2. Os ensaios usaram kubectl do próprio nó.

Com autorização, kind, Helm e Terraform foram instalados somente em `infra/.local/tools/`, ignorado pelo Git, com checksums oficiais conferidos. Para usar essa instalação na sessão, a partir da raiz:

```powershell
$env:Path = (Join-Path (Get-Location) 'infra/.local/tools') + ';' + $env:Path
docker version
docker compose version
kind version
helm version --short
terraform version
```

O host deve permitir TLS autenticado entre Terraform/plugins e ferramentas/API Kubernetes. Após o ajuste do Norton, o ciclo foi executado no terminal Windows do usuário com a validação de certificados mantida.

## Compose de entendimento

Execute na raiz e forneça uma senha externa, sem incluí-la no histórico. A URI usa a mesma credencial, com componentes codificados:

```powershell
$credential = Read-Host 'Senha descartável do Postgres' -AsSecureString
$env:POSTGRES_PASSWORD = [Net.NetworkCredential]::new('', $credential).Password
$env:POSTGRES_USER = 'mural'
$env:POSTGRES_DB = 'mural'
$dbUser = [uri]::EscapeDataString($env:POSTGRES_USER)
$dbPassword = [uri]::EscapeDataString($env:POSTGRES_PASSWORD)
$dbName = [uri]::EscapeDataString($env:POSTGRES_DB)
$env:DATABASE_URL = "postgresql://${dbUser}:${dbPassword}@db:5432/${dbName}?sslmode=disable"
docker compose config --quiet
docker compose up -d --wait --wait-timeout 300
```

Abra [o Mural](http://localhost:8080), publique e leia um recado. A ordem é banco saudável → migração concluída → API saudável → front. O Compose usa as quatro imagens oficiais exigidas, com `go run .`, volume persistente e mounts dos arquivos existentes.

Ao encerrar o ensaio, remova somente seus dados descartáveis:

```powershell
docker compose down --volumes
Remove-Item Env:POSTGRES_PASSWORD,Env:DATABASE_URL
$credential = $null
$dbPassword = $null
```

## Terraform — procedimento validado

Encerre o Compose e o cluster de ensaio antes do ambiente final. Não crie o cluster final nem instale releases manualmente. A partir da raiz:

```powershell
$credential = Read-Host 'Senha do Postgres para este ciclo' -AsSecureString
$env:TF_VAR_postgres_password = [Net.NetworkCredential]::new('', $credential).Password
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform fmt -check
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform apply
```

Senha obrigatória, sem default: reutilize a mesma nos dois applies e destroy. Rotação de senha de banco já inicializado não faz parte deste fluxo. O host padrão é [mural.localtest.me](http://mural.localtest.me), resolvendo para 127.0.0.1. Outputs mostram URL e kubeconfig exclusivo, sem senha. Host/portas podem ser definidos antes do primeiro apply por `TF_VAR_host`, `TF_VAR_http_port` e `TF_VAR_https_port`. O host padrão foi aberto no navegador e a publicação pelo formulário foi confirmada na API.

```powershell
$kubeconfig = terraform -chdir=infra/terraform output -raw kubeconfig_path
kubectl --kubeconfig $kubeconfig -n mural get pods,jobs,pvc,ingress
kubectl --kubeconfig $kubeconfig -n mural logs -l app.kubernetes.io/component=migrate --timestamps
```

Publique um recado no navegador. Confira seed e migração antes da primeira readiness; recrie somente `mural-postgres-0`, preservando PVC, e confirme o mesmo recado após recuperação. Durante indisponibilidade controlada do banco, a API deve ficar NotReady, com `/healthz` funcionando e sem reinícios. Não publique Secrets, valores Helm nem planos sensíveis.

Sem alterar fontes/entradas e com o ambiente recuperado:

```powershell
terraform -chdir=infra/terraform apply
# Exigir: 0 added, 0 changed, 0 destroyed; sem novo build/load ou Job.
terraform -chdir=infra/terraform destroy
terraform -chdir=infra/terraform state list
kind get clusters
docker ps -a --filter name=mural-mba --format '{{.Names}}'
docker image ls 'mural-mural-mba-*'
Test-Path infra/terraform/.mural-mural-mba.kubeconfig
Remove-Item Env:TF_VAR_postgres_password
$credential = $null
```

Exigir estado vazio, ausência de cluster/nós/volumes exclusivos e tags construídas e `Test-Path=False`. Compare o inventário anterior com o posterior para comprovar preservação de recursos alheios. Registre também o inventário imediatamente antes do destroy, especialmente quando outros projetos usam o mesmo Docker durante o ensaio. A solução não executa prune global nem remove imagens base ou caches compartilhados.

## Decisões

- API multi-stage: `CGO_ENABLED=0`, binário sem símbolos, estágio final `scratch`, usuário 65532. Front nginx processa o template original e `API_UPSTREAM` no boot.
- Chart: duas réplicas API/front, StatefulSet Postgres com PVC padrão do kind, ConfigMap, Secret com URI codificada e `secretKeyRef`; probes distintas e requests/limits em todos os contêineres.
- Migração em Job normal: espera limitada, `psql --single-transaction -v ON_ERROR_STOP=1`, schema e seed juntos; nome determinístico por conteúdo/especificação, sem hooks nem TTL. Helm aguarda Jobs e workloads. Ingress preserva `/api`.
- Terraform 1.13.5; providers [kind 0.11.0](https://github.com/tehcyx/terraform-provider-kind/blob/v0.11.0/docs/resources/cluster.md), [Helm 2.14.1](https://github.com/hashicorp/terraform-provider-helm/blob/v2.14.1/docs/resources/release.md), Kubernetes 2.36.0; [chart Traefik 34.4.1](https://github.com/traefik/traefik-helm-chart/blob/v34.4.1/traefik/values.yaml). Providers usam atributos de conexão do kind, sem leitura prematura de arquivo. Kubeconfig exclusivo; preflight rejeita colisões de cluster/contexto.
- Build/load em `terraform_data`, PowerShell com propagação de erros, tags/gatilhos por conteúdo e identidade do cluster, digest do chart na release. Destroy limita a limpeza às tags e arquivo exclusivos; grafo preserva o cluster durante remoção de releases/namespaces. Hashes/tags foram verificados com Terraform console em cópias descartáveis: entradas idênticas permanecem estáveis e alterações de API, web, Dockerfile e chart afetam somente seus gatilhos. Segundo apply real sem mudanças, sem provisioners e com identidades preservadas.
- `.env`, tfvars, state, planos, kubeconfig e `infra/.local/` são ignorados pelo Git. State e metadados Helm podem conter senha: `sensitive` não significa criptografia.

## Evidências — 07/11/2026

O ciclo integrado `final-20261107-150712` partiu sem recursos do Mural e foi provisionado pelo Terraform no Windows. Os ensaios isolados cobriram falha SQL e reuso de imagens. Registros em `infra/.local/` são privados, ignorados pelo Git e alguns contêm entradas descartáveis; não publique esse diretório.

| ID | Evidência / pendência |
|---|---|
| D1 | Aprovado: build linux/amd64; scratch respondeu `/healthz` 200; filesystem exportado sem código/toolchain, somente binário e arquivos de runtime gerados pelo Docker. |
| D2 | Aprovado: `golang:1.23-alpine` **246.135.626 bytes**; `mural-check-api:local` **9.379.992 bytes**, mesma plataforma. Redução aproximada de **96,2%**. |
| D3 | Aprovado: mesma imagem web com GET/POST usando dois upstreams, sem rebuild. |
| K1 | Aprovado: lint/overrides/renderização, release aguardando Jobs/workloads e GET/POST pelo navegador no host configurado. |
| K2 | Aprovado no ciclo integrado: recado original ID 2 preservado na API e no navegador após recriação do pod Postgres; PVC Bound com o mesmo UID. |
| K3 | Aprovado: senha externa com espaço/caracteres reservados; Secret e referências funcionais; ausência de senha gera erro explícito. |
| K4 | Aprovado no ciclo integrado: banco escalado para zero, API NotReady, `healthz=ok`, sem reinícios adicionais após mais de 30s; recuperação pelo Ingress após um 503 transitório, em 1,1 s. |
| K5 | Aprovado no ciclo integrado: inspeção confirmou CPU/memória requests/limits em API, web, Postgres, Job e Traefik. |
| K6 | Aprovado: schema e seed em transação única; seed às 18:09:22 UTC, API Ready às 18:09:24 UTC, Job concluído antes do retorno do primeiro apply às 18:09:26 UTC. Ensaio SQL inválido confirmou rollback, Job Failed e API sem readiness. |
| T1 | Aprovado: um apply limpo criou 8 recursos, Job concluído e recado Navegador-8cba5f3d publicado pelo formulário e encontrado na API. |
| T2 | Aprovado: segundo apply real com **0 added, 0 changed, 0 destroyed**; identidades preservadas, sem novo build/load ou Job. |
| T3 | Aprovado: **8 destroyed**, estado vazio, cluster/nós/volume/tags/kubeconfig exclusivos ausentes e kubeconfig global preservado. Inventário confirmou os 25 contêineres prévios com mesmos IDs e preservação dos 156 volumes e 229 tags prévios. |
| T4 | Aprovado: providers organizados e fixados; init/fmt/validate Windows e bootstrap real com Helm provider 2.14.1. |
| C1 | Revisão aprovada: sem credencial funcional em manifests/defaults; `git check-ignore` confirmou proteção de entradas/artefatos locais. |
| C2 | Aprovado: diff vazio em `app/api` e `app/web`; hashes das migrations originais e do chart iguais. |

Medição após construir com os Dockerfiles entregues:

```powershell
docker build --platform linux/amd64 -f app/docker/api.Dockerfile -t mural-check-api:local .
docker build --platform linux/amd64 -f app/docker/web.Dockerfile -t mural-check-web:local .
docker image inspect golang:1.23-alpine mural-check-api:local --format '{{.RepoTags}} {{.Os}}/{{.Architecture}} {{.Size}}'
```

Compose: POST/GET e publicação pelo formulário no navegador aprovados; migration exit 0 antes da API. Ensaio com SQL inválido: exit 3, API sem início e rollback. Os dois projetos Compose e volumes exclusivos foram removidos.

## Auditoria final do destroy

O ciclo aprovado começou às **15:07:12 BRT** e terminou às **15:33:17 BRT** de 07/11/2026. O relatório local `infra/.local/final-20261107-150712/report.json` registra `PASS`. Os inventários inicial, imediatamente antes do destroy e depois do destroy foram preservados no mesmo diretório ignorado.

O destroy removeu 8 recursos. A auditoria confirmou estado vazio, ausência do cluster/nós, remoção do volume exclusivo, tags gerenciadas e kubeconfig exclusivo, com kubeconfig global inalterado. A comparação confirmou preservação de todos os contêineres, volumes e tags de imagens prévios, sem diferenças.

A divergência observada no ciclo anterior permanece documentada em seus relatórios privados e no histórico de `tasks.md`; sua causa não foi atribuída sem evidência. O novo ciclo comprova integralmente T3 com um novo inventário, sem dispensar verificações nem alterar os relatórios anteriores.

Revisão final: `terraform fmt -check`, `helm lint`, `docker compose config --quiet`, validação estrita do OpenSpec e `git diff --check` aprovados. O ciclo Windows também executou init e validate com sucesso. API, front e migrations permanecem idênticos aos originais; credenciais de ensaio não constam nos arquivos entregáveis.

A entrega mantém Dockerfiles em `app/docker/` e infraestrutura em `infra/`, sem HPA, carga ou automações de bônus. Os roteiros temporários de validação estão somente em `infra/.local/`, ignorado pelo Git. Sem commit, push ou arquivamento automático.
