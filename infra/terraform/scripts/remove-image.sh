#!/bin/sh
set -eu

image_id=$(docker image ls --quiet "$MURAL_IMAGE")
if [ -n "$image_id" ]; then
  docker image rm "$MURAL_IMAGE"
fi
