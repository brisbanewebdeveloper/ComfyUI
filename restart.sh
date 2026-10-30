#!/bin/bash

set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [ -f .env ]; then
    . .env
fi

cd -- "${COMFYUI_HOST_ROOT:-$PWD}"
compose=(docker compose --project-directory "$PWD" -f "$PWD/docker-compose.yml")
"${compose[@]}" build comfyui

# Leave a running generation alone, including one started during the build.
if [ -n "$("${compose[@]}" ps --status running -q comfyui)" ]; then
    "${compose[@]}" exec -T comfyui python - <<'PY'
import json
from urllib.request import urlopen

with urlopen('http://127.0.0.1:8188/queue', timeout=10) as response:
    queue = json.load(response)
if queue['queue_running'] or queue['queue_pending']:
    raise SystemExit('ComfyUI has queued work; wait for it to finish before restarting.')
PY
fi

"${compose[@]}" up -d --no-deps --no-build --force-recreate comfyui
