#!/bin/bash

set -e

. .env

cd "$COMFYUI_HOST_ROOT"
docker compose down
docker compose up -d --remove-orphans
