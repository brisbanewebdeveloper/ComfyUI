## Docker Compose Runner

This guide explains how to build and launch ComfyUI with the provided Docker assets.

### Prerequisites

- Docker Engine 24+ and Docker Compose v2 (bundled with modern Docker releases)
- At least 16 GB of host RAM for GPU workloads (CPU-only runs can work with less)
- Optional: NVIDIA Container Toolkit if you plan to pass a GPU into the container

### Directory Layout

The Compose file mounts several directories to persist assets and results. Create them before the first run if they do not already exist:

```
models/
input/
output/
custom_nodes/
user/
```

### Quick Start

```bash
docker compose up --build
```

This builds the image from the local `Dockerfile`, starts the `comfyui` service, and publishes the UI on <http://localhost:8188>.

### Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `COMFYUI_PORT` | `8188` | Host port exposed for the web UI |
| `INSTALL_TORCH` | `0` | Set to `1` to reinstall `torch`, `torchvision`, and `torchaudio` during build |
| `TORCH_INDEX_URL` | _(empty)_ | Optional custom index for fetching CUDA/ROCm wheels when `INSTALL_TORCH=1` |
| `NVIDIA_VISIBLE_DEVICES` | `all` | Limits which host GPUs are visible inside the container |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,utility` | Requests compute capability from the NVIDIA runtime |
| `GPU_COUNT` | `all` | Controls how many GPUs Docker reserves for the service |

Set these in a `.env` file or export them in the shell before running `docker compose`.

### GPU Support (Optional)

1. Install the NVIDIA Container Toolkit following the official documentation.
2. Rebuild with the desired PyTorch wheel:

```bash
export INSTALL_TORCH=1
export TORCH_INDEX_URL=https://download.pytorch.org/whl/cu121
docker compose build
```

3. Launch with GPU access:

```bash
docker compose up --gpus all
```

You can target specific devices by replacing `--gpus all` with `--gpus 'device=0'`.

Need a fresh build and GPU access together? Combine the flags:

```bash
docker compose up --build --gpus all
```

### Stopping and Cleaning Up

- Stop the stack: `docker compose down`
- Remove images: `docker compose down --rmi local`
- Purge volumes (removes cached data): `docker compose down --volumes`

### Troubleshooting

- **Port already in use**: Change `COMFYUI_PORT` to a free value and restart.
- **Torch/CUDA mismatch**: Rebuild with `INSTALL_TORCH=1` pointing to the correct wheel index.
- **Permission issues**: Ensure the mounted directories are writable by the user running Docker.
