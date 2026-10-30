# Docker Compose Runner

Run commands from this checkout. The normal build produces `comfyui:cu130`: PyTorch 2.9.1+cu130, torchvision 0.24.1+cu130, torchaudio 2.9.1+cu130 and CUDA 13.0. Both PyTorch base images are pinned by digest. SageAttention 2.2.0 is compiled for this stack from commit `eb615cf6cf4d221338033340ee2de1c37fbdba4a`, targeting the production RTX 4090 (SM 8.9). This image requires a CUDA 13 compatible NVIDIA driver and NVIDIA Container Toolkit.

## Build and restart

Coordinate with generation clients first: keep new submissions paused and wait for their active work and ComfyUI's queue to empty. Do not interrupt a generation or stop competing services.

```bash
cd /mnt/samsung-980pro/src/github.com/brisbanewebdeveloper/ComfyUI
docker compose config
./restart.sh
```

`restart.sh` builds while the current service runs, checks its queue immediately before replacement, then recreates only `comfyui`. It refuses a nonempty queue; this check does not lock out new client submissions. It uses the maintained Compose file and `.env` regardless of the caller's working directory. The equivalent commands are:

```bash
docker compose build comfyui
docker compose up -d --no-deps --no-build --force-recreate comfyui
```

`docker compose up -d --no-deps --build comfyui` also builds and launches this stack. `docker compose restart comfyui` restarts the existing container without selecting a new image. Use `restart.sh` after source changes.

`docker/runtime-constraints.txt` records the accepted runtime's installed dependency versions. All build-time pip installs use these constraints, including isolated trust-maintenance installs, so a custom-node requirement cannot silently replace torch. Incompatible requirements fail the build. The build also asserts the exact torch trio and CUDA version. `INSTALL_TORCH` and `TORCH_INDEX_URL` no longer select the runtime; stale values in `.env` have no effect. Review constraints and rebuild compiled extensions together before any future stack upgrade.

The CA distrust checks, pinned pip/certifi, hash-checked FaceRefine wheels, NVIDIA VFX package and existing custom-node requirements remain in the build. A reviewed CUDA 13 application image can still be supplied through the `COMFYUI_APP_IMAGE` build argument for CA-only maintenance; the final version assertion rejects an older CUDA stack.

## Runtime checks

```bash
docker compose exec -T comfyui python docker/runtime-smoke.py --fast fp16_accumulation
curl --fail http://127.0.0.1:18188/system_stats
curl --fail http://127.0.0.1:18188/queue
docker inspect comfyui --format '{{.Image}}'
docker image inspect comfyui:cu130 --format '{{.Id}}'
```

Use your configured host port if it differs. The smoke script checks exact packages, GPU availability, fp16 accumulation, Sage FP8++ against PyTorch attention, native Comfy Kitchen CUDA FP8 quantization/dequantization and fp16 convolution, torchvision CUDA NMS and torchaudio CUDA filtering. These are small runtime checks, not end-to-end generation validation. Check `/object_info` for the nodes used by your saved workflows after recreation.

The accepted default stays Singularity V2 at 448×800, NVIDIA regeneration at 704×1248, 8+3 steps, Sage FP8++, 16,384-row MLP chunks, native CUDA sampling and native INT8 final video VAE. Compose retains `--fast fp16_accumulation`. No forced Triton sampling or experimental workflow is enabled by this build. The quality-approved 15-second candidate took 258.798 seconds in one historical run; that is not a runtime guarantee.

## Persistent configuration

Compose preserves `models/`, `input/`, `output/`, `custom_nodes/`, `user/` and `temp/` through their existing bind mounts. `user/` and `temp/` are excluded from the image build context so changing caches and runtime state do not get baked into rebuilds. The image contains application source; runtime assets and installed node source remain in those mounts. Keep the mounted custom-node requirements available in the build context. Create the directories before a first launch and make them writable by the configured UID/GID.

| Variable | Default | Purpose |
| --- | --- | --- |
| `COMFYUI_IMAGE` | `comfyui:cu130` | Build/run tag; use a preserved tag only with `--no-build` for rollback |
| `COMFYUI_PORT` | `8188` | Host port (this deployment uses `18188`) |
| `COMFYUI_UID`, `COMFYUI_GID` | `1000` | Runtime user and group |
| `NVIDIA_VISIBLE_DEVICES` | `all` | Visible GPU devices |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,utility` | NVIDIA runtime capabilities |
| `GPU_COUNT` | `all` | GPU reservation count |

Existing cache paths, pre-prompt command, telemetry setting, ports, GPU reservation and startup options remain in Compose. Set variables in `.env` or the shell.

## Rollback

Keep these local images; never build over their tags or prune them:

| Image | Recorded image ID |
| --- | --- |
| `comfyui:h3-cu130-production-20261030` | `sha256:4f95e254277809214d96c3afd7e23493327a5f258b25e3d1d16dde6670602385` |
| `comfyui:h3-rollback-cu130-triton-20261031` | Same image ID; the sampling profile lives in the workflow |
| `comfyui:h3-rollback-cu128-20261030` | `sha256:11c21f921120d65556f24d202a81e673f87316654a94d44efdf1a12ce4715e64` |

While generation clients are quiescent and the queue is empty, restore the accepted CUDA 13 image without building:

```bash
COMFYUI_IMAGE=comfyui:h3-cu130-production-20261030 docker compose up -d --no-deps --no-build --pull never comfyui
curl --fail http://127.0.0.1:18188/system_stats
```

This preserves the current native-CUDA workflow. To return to the maintained build, run `./restart.sh` with `COMFYUI_IMAGE` unset. Do not run `restart.sh` with a rollback tag exported: it builds the selected tag.

CUDA 12.8 is an older emergency rollback and needs its matching retained workflow. With generation clients quiescent, the following restores only the four project-selection fields from the original deployment snapshot. It accepts only the known current/previous defaults and preserves all workflow records, graphs, notes and unrelated project settings. The original promotion scripts predate the notes columns; their whole-row preservation comparisons can fail after that schema change.

```bash
docker exec -i -e PYTHONPATH=/app ig-marketing-worker-1 python - <<'PY'
import json
from pathlib import Path
from psycopg.types.json import Jsonb
from worker.store import Store

saved = json.loads(Path('/data/jobs/minimax-cuda13-20261030/promotion-before.json').read_text())
previous = saved['project']['config']
store = Store()
with store.db.transaction():
    current = store.one('SELECT config FROM projects WHERE id=%s FOR UPDATE',
                        (saved['project']['id'],))['config']
    assert current['baseWorkflowId'] in {
        'ab0722e3-23a7-56c2-85df-e2463084c6a8',
        '624a7615-3097-5308-b534-01e2efa8279f',
        previous['baseWorkflowId'],
    }, 'Project default changed; review before rollback'
    store.one('SELECT id FROM workflow_bases WHERE id=%s', (previous['baseWorkflowId'],))
    for field in ['baseWorkflowId', 'generationMode', 'requiredVideoModel', 'videoPromptTemplate']:
        if field in previous:
            current[field] = previous[field]
        else:
            current.pop(field, None)
    store.execute('UPDATE projects SET config=%s WHERE id=%s',
                  (Jsonb(current), saved['project']['id']))
PY
COMFYUI_IMAGE=comfyui:h3-rollback-cu128-20261030 docker compose up -d --no-deps --no-build --pull never comfyui
curl --fail http://127.0.0.1:18188/system_stats
```

This selects the retained Larry 448×800 + NVIDIA Regenerate 704×1248 8+3 profile (`1e23e0de-963d-5c8e-80a7-a73bf0d15868`). To restore current production later, run `./restart.sh`, then reselect the retained native-CUDA profile (`ab0722e3-23a7-56c2-85df-e2463084c6a8`) and its saved settings in ig-marketing. A runtime rollback alone never changes workflow selection. Resume generation clients only after API readiness and the matching workflow are verified. Workflow rollback was reviewed against the existing snapshots but was not executed during runtime verification.

For permissions or port failures, correct the configured UID/GID, directory ownership or `COMFYUI_PORT`. For a dependency conflict, review the failing requirement against the accepted constraints rather than installing a different torch version in the container.
