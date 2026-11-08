#!/bin/sh
set -eu

if [ -e "$MURAL_KUBECONFIG" ]; then
  echo "Kubeconfig exclusivo já existe; não sobrescrever arquivo fora deste estado: $MURAL_KUBECONFIG" >&2
  exit 1
fi

if ! clusters=$(kind get clusters 2>/dev/null); then
  echo 'Não foi possível consultar clusters kind' >&2
  exit 1
fi
if printf '%s\n' "$clusters" | grep -qx "$MURAL_CLUSTER"; then
  echo "Nome de cluster já utilizado fora deste estado: $MURAL_CLUSTER" >&2
  exit 1
fi

if ! contexts=$(kubectl config get-contexts -o name); then
  echo 'Não foi possível consultar os contextos locais' >&2
  exit 1
fi
if printf '%s\n' "$contexts" | grep -qx "kind-$MURAL_CLUSTER"; then
  echo "Contexto global já existente; escolha outro cluster_name: kind-$MURAL_CLUSTER" >&2
  exit 1
fi
