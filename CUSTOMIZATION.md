# Dockerized Version

This branch adds a Docker Compose based local runner on top of upstream ComfyUI `master`. It is intended for a persistent, GPU-capable container setup while keeping models, inputs, outputs, custom nodes, user data, and temporary files on the host.

### Customizations Compared With `master`

- Adds a `Dockerfile` based on `pytorch/pytorch:2.4.0-cuda12.1-cudnn9-runtime`.
- Adds `docker-compose.yml` with the `comfyui` service, host port mapping, NVIDIA GPU reservation, and bind mounts for `models`, `input`, `output`, `custom_nodes`, `user`, and `temp`.
- Adds `.dockerignore` and `.rgignore` entries to keep large model files, generated outputs, caches, and local custom nodes out of Docker build context and repository searches.
- Expands `manager_requirements.txt` from the upstream Manager package pin into explicit Manager/runtime dependencies, including `diffusers==0.35.2`, `accelerate`, and `omegaconf` for the installed custom node set.
- Adds `custom_nodes/pre_prompt_command`, a local custom-node hook that can run an opt-in shell command before each prompt starts.
- Adds helper scripts: `restart.sh`, `down.sh`, and `merge.sh`.
- Ignores local-only files such as `.env`, `.history/`, and generated `openapi.yaml`.

### Quick Start

```bash
docker compose up --build
```

Open <http://localhost:8188> after the service starts.

### Configuration

Set these values in `.env` or export them before running Compose:

| Variable | Default | Purpose |
| --- | --- | --- |
| `COMFYUI_PORT` | `8188` | Host port for the ComfyUI web UI |
| `COMFYUI_UID` | `1000` | Container user id for mounted files |
| `COMFYUI_GID` | `1000` | Container group id for mounted files |
| `INSTALL_TORCH` | `0` | Set to `1` to reinstall `torch`, `torchvision`, and `torchaudio` during image build |
| `TORCH_INDEX_URL` | empty | Optional PyTorch wheel index used when `INSTALL_TORCH=1` |
| `NVIDIA_VISIBLE_DEVICES` | `all` | GPUs visible inside the container |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,utility` | NVIDIA runtime capabilities requested by the service |
| `GPU_COUNT` | `all` | Number of GPUs reserved for the service |
| `COMFYUI_PRE_PROMPT_COMMAND` | empty | Optional shell command run before each prompt starts |
| `COMFYUI_PRE_PROMPT_COMMAND_TIMEOUT` | `10` | Timeout in seconds for the pre-prompt command |

Use `./restart.sh` to rebuild and restart with the local `.env` values, and `./down.sh` to stop the Compose stack.

### Pre-Prompt Command Hook

The pre-prompt hook is disabled unless `COMFYUI_PRE_PROMPT_COMMAND` is set. It is useful for local setup tasks such as asking a same-host Ollama service to unload a model before ComfyUI starts a workflow.

For `.env`, keep the command on one line and escape JSON quotes:

```bash
COMFYUI_PRE_PROMPT_COMMAND=curl -sS --fail --max-time 10 -H "Content-Type: application/json" http://host.docker.internal:11434/api/generate -d "{\"model\":\"YOUR_MODEL\",\"prompt\":\"\",\"stream\":false,\"keep_alive\":0}"
COMFYUI_PRE_PROMPT_COMMAND_TIMEOUT=10
```

Replace `YOUR_MODEL` with the exact loaded Ollama model name. The Compose service maps `host.docker.internal` to the Docker host so the container can reach the host Ollama API.

If quoting becomes awkward, put the command in a script mounted under `/app/user` and call that instead:

```bash
COMFYUI_PRE_PROMPT_COMMAND=sh /app/user/unload_ollama.sh
```

Rebuild the image after changing Docker dependencies such as `curl`:

```bash
docker compose up -d --build
```
