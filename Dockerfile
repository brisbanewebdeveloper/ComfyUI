# syntax=docker/dockerfile:1.6
ARG COMFYUI_APP_IMAGE=application
FROM pytorch/pytorch:2.9.1-cuda13.0-cudnn9-devel@sha256:d8d98ebdc7006e495d263d8734eb7bb2d19803419d9315159fe15c62d5bad1bd AS sageattention-builder

ARG SAGEATTENTION_COMMIT=eb615cf6cf4d221338033340ee2de1c37fbdba4a
ENV TORCH_CUDA_ARCH_LIST=8.9 \
    EXT_PARALLEL=2 \
    MAX_JOBS=4

COPY docker/runtime-constraints.txt /opt/comfyui/runtime-constraints.txt
ENV PIP_CONSTRAINT=/opt/comfyui/runtime-constraints.txt
RUN python -m pip install --index-url https://download.pytorch.org/whl/cu130 \
    torch==2.9.1+cu130 torchvision==0.24.1+cu130 torchaudio==2.9.1+cu130

RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/thu-ml/SageAttention.git /tmp/SageAttention && \
    cd /tmp/SageAttention && \
    git checkout "$SAGEATTENTION_COMMIT" && \
    pip wheel --no-build-isolation --no-deps --wheel-dir /wheels .

FROM pytorch/pytorch:2.9.1-cuda13.0-cudnn9-runtime@sha256:60f22fb80755fd0b470fb47928dbd55816aa9f847edd95cf43c93253507a9ddf AS application

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    UV_CACHE_DIR=/tmp/uv-cache \
    TRITON_CACHE_DIR=/tmp/triton-cache \
    PIP_CONSTRAINT=/opt/comfyui/runtime-constraints.txt

COPY docker/runtime-constraints.txt /opt/comfyui/runtime-constraints.txt

WORKDIR /app

RUN if ! getent group 1000 >/dev/null; then groupadd --gid 1000 comfyui; fi && \
    if ! getent passwd 1000 >/dev/null; then useradd --uid 1000 --gid 1000 --no-create-home --shell /usr/sbin/nologin comfyui; fi

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

RUN set -eux; \
    pip install --upgrade pip==26.2.2; \
    pip install --index-url https://download.pytorch.org/whl/cu130 \
        torch==2.9.1+cu130 torchvision==0.24.1+cu130 torchaudio==2.9.1+cu130

RUN pip install --no-cache-dir -r /tmp/requirements.txt

# NVIDIA's VFX wheel is published on its package index and is required by the
# RTX Video Super Resolution custom node.
RUN pip install --no-cache-dir \
    --index-url https://pypi.nvidia.com/ \
    nvidia-vfx==0.1.0.1

COPY --from=sageattention-builder /wheels/sageattention-2.2.0-*.whl /tmp/
RUN pip install --no-cache-dir --no-deps /tmp/sageattention-2.2.0-*.whl && \
    rm /tmp/sageattention-2.2.0-*.whl

COPY . /app

RUN pip install --no-cache-dir \
    -r /app/manager_requirements.txt \
    -r /app/custom_nodes/comfyui-easy-use/requirements.txt \
    -r /app/custom_nodes/ComfyUI-outputlists_combiner/requirements.txt \
    -r /app/custom_nodes/ComfyUI-GGUF/requirements.txt \
    -r /app/custom_nodes/RES4LYF/requirements.txt \
    -r /app/custom_nodes/ComfyUI-UtilsCollection/requirements.txt \
    -r /app/custom_nodes/VideoX-Fun/requirements.txt

RUN mkdir -p /app/models /app/input /app/output /app/custom_nodes /app/user

EXPOSE 8188

CMD ["python", "-u", "main.py", "--listen", "0.0.0.0"]

# CA-only maintenance can reuse a reviewed application image without recompiling CUDA.
FROM ${COMFYUI_APP_IMAGE} AS runtime
USER root
COPY docker/runtime-constraints.txt /opt/comfyui/runtime-constraints.txt
ENV PIP_CONSTRAINT=/opt/comfyui/runtime-constraints.txt
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && dpkg --compare-versions "$(dpkg-query -W -f='${Version}' ca-certificates)" ge '20260816ubuntu0.22.04.1' \
    && rm -rf /var/lib/apt/lists/*
RUN python -m pip --isolated install --index-url https://pypi.org/simple \
    --constraint /opt/comfyui/runtime-constraints.txt \
    --cert /etc/ssl/certs/ca-certificates.crt --no-cache-dir --only-binary=:all: \
    --no-deps --upgrade pip==26.2.2 certifi==2026.10.23
COPY docker/secure-trust.py /tmp/secure-trust.py
RUN python /tmp/secure-trust.py && rm /tmp/secure-trust.py

# FaceRefine dependencies are reviewed wheels; retain the CUDA and OpenCV stack.
COPY docker/h3-facerefine-requirements.txt /tmp/h3-facerefine-requirements.txt
RUN python -m pip --isolated install --index-url https://pypi.org/simple \
    --constraint /opt/comfyui/runtime-constraints.txt \
    --cert /etc/ssl/certs/ca-certificates.crt --no-cache-dir --only-binary=:all: \
    --no-deps --require-hashes -r /tmp/h3-facerefine-requirements.txt \
    && rm /tmp/h3-facerefine-requirements.txt

RUN python - <<'PY'
import torch
import torchvision
import torchaudio
assert (torch.__version__, torchvision.__version__, torchaudio.__version__, torch.version.cuda) == \
       ('2.9.1+cu130', '0.24.1+cu130', '2.9.1+cu130', '13.0')
PY
