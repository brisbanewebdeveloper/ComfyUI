#!/bin/bash

set -e

. .env

cd "$COMFYUI_HOST_ROOT"
docker compose down
