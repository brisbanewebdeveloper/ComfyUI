# syntax=docker/dockerfile:1.6
FROM pytorch/pytorch:2.8.0-cuda12.8-cudnn9-devel AS sageattention-builder

ARG SAGEATTENTION_COMMIT=eb615cf6cf4d221338033340ee2de1c37fbdba4a
ENV TORCH_CUDA_ARCH_LIST=8.9 \
    EXT_PARALLEL=2 \
    MAX_JOBS=8

RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/thu-ml/SageAttention.git /tmp/SageAttention && \
    cd /tmp/SageAttention && \
    git checkout "$SAGEATTENTION_COMMIT" && \
    pip wheel --no-build-isolation --no-deps --wheel-dir /wheels .

FROM pytorch/pytorch:2.8.0-cuda12.8-cudnn9-runtime

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    UV_CACHE_DIR=/tmp/uv-cache \
    TRITON_CACHE_DIR=/tmp/triton-cache

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        ffmpeg \
        libgl1 \
        libegl1 \
        libglib2.0-0 \
        libsm6 \
        libxrender1 \
        libxext6 \
        curl \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt

ARG INSTALL_TORCH=0
ARG TORCH_INDEX_URL=
RUN set -eux; \
    pip install --upgrade pip; \
    if [ "$INSTALL_TORCH" = "1" ]; then \
        if [ -n "$TORCH_INDEX_URL" ]; then \
            pip install torch torchvision torchaudio --index-url "$TORCH_INDEX_URL"; \
        else \
            pip install torch torchvision torchaudio; \
        fi; \
    fi

RUN python - <<'PY'
from pathlib import Path
src = Path("/tmp/requirements.txt")
skip = {"torch", "torchvision", "torchaudio"}
out = []
for line in src.read_text().splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        out.append(line)
        continue
    candidate = stripped.split(";", 1)[0]
    candidate = candidate.split("[", 1)[0]
    for sep in ("==", ">=", "<=", "~=", "!=", "===", ","):
        candidate = candidate.split(sep, 1)[0]
    candidate = candidate.strip()
    if candidate in skip:
        continue
    out.append(line)
Path("/tmp/requirements-no-torch.txt").write_text("\n".join(out) + "\n")
PY

RUN pip install --no-cache-dir -r /tmp/requirements-no-torch.txt

COPY --from=sageattention-builder /wheels/sageattention-2.2.0-*.whl /tmp/
RUN pip install --no-cache-dir /tmp/sageattention-2.2.0-*.whl && \
    rm /tmp/sageattention-2.2.0-*.whl

COPY . /app

RUN pip install --no-cache-dir \
    -r /app/manager_requirements.txt \
    -r /app/custom_nodes/comfyui-easy-use/requirements.txt \
    -r /app/custom_nodes/ComfyUI-outputlists_combiner/requirements.txt \
    -r /app/custom_nodes/ComfyUI-GGUF/requirements.txt \
    -r /app/custom_nodes/RES4LYF/requirements.txt \
    -r /app/custom_nodes/ComfyUI-UtilsCollection/requirements.txt

RUN mkdir -p /app/models /app/input /app/output /app/custom_nodes /app/user

EXPOSE 8188

CMD ["python", "-u", "main.py", "--listen", "0.0.0.0"]
