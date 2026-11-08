#!/bin/sh
# Roda apply → apply → destroy dentro do toolbox Linux, numa cópia isolada do repositório.
set -eu

: "${TF_VAR_postgres_password:?Defina TF_VAR_postgres_password (ex.: docker run --env-file .env)}"

work=/work
mkdir -p "$work"
tar -C /src \
  --exclude=./.git \
  --exclude=./infra/.local \
  --exclude=./infra/terraform/.terraform \
  --exclude='./infra/terraform/terraform.tfstate*' \
  --exclude='./infra/terraform/.mural-*' \
  -cf - . | tar -C "$work" -xf -
cd "$work"

tf() { terraform -chdir=infra/terraform "$@"; }

cleanup() {
  status=$?
  if [ -n "$(tf state list 2>/dev/null)" ]; then
    echo '==> destroy de segurança'
    tf destroy -auto-approve -input=false -no-color || status=1
  fi
  exit "$status"
}
trap cleanup EXIT

step() { echo; echo "==> $*"; }

step 'init'
tf init -input=false -no-color >/dev/null

step '1º apply'
tf apply -auto-approve -input=false -no-color

url=$(tf output -raw mural_url)
step "verificando $url"
attempt=0
until curl -fsS -o /dev/null "$url/"; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || { echo 'front não respondeu' >&2; exit 1; }
  sleep 2
done
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"author":"linux-cycle","content":"teste no toolbox Linux"}' "$url/api/messages"
echo
curl -fsS "$url/api/messages" | grep -q linux-cycle
echo 'front e API ok'

step '2º apply (idempotência)'
out=$(tf apply -auto-approve -input=false -no-color)
echo "$out" | grep 'Resources:'
echo "$out" | grep -q 'Resources: 0 added, 0 changed, 0 destroyed' || { echo 'segundo apply alterou recursos' >&2; exit 1; }

step 'destroy'
tf destroy -auto-approve -input=false -no-color | grep 'Resources:'
[ -z "$(tf state list)" ] || { echo 'state não ficou vazio' >&2; exit 1; }
if kind get clusters 2>/dev/null | grep -qx "${TF_VAR_cluster_name:-mural-mba}"; then
  echo 'cluster kind ainda existe' >&2
  exit 1
fi

step 'ciclo Linux aprovado'
