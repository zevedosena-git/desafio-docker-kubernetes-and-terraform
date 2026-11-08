#!/bin/sh
set -eu

docker build -f "$MURAL_DOCKERFILE" -t "$MURAL_IMAGE" "$MURAL_REPO_ROOT"
kind load docker-image "$MURAL_IMAGE" --name "$MURAL_CLUSTER"
