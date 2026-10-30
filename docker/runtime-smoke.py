"""Execute small production CUDA kernels; run with --fast fp16_accumulation."""

import json
import sys
from importlib.metadata import version
from pathlib import Path
from time import perf_counter

import torch
import torchvision
import torchaudio
from sageattention import sageattn_qk_int8_pv_fp8_cuda

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import comfy.options

comfy.options.enable_args_parsing()
import comfy.model_management
import comfy_kitchen as ck


def main() -> None:
    expected = {'torch': '2.9.1+cu130', 'torchvision': '0.24.1+cu130',
                'torchaudio': '2.9.1+cu130', 'sageattention': '2.2.0',
                'triton': '3.5.1', 'comfy-kitchen': '0.2.40', 'comfy-aimdo': '0.6.0'}
    actual = {name: version(name) for name in expected}
    assert actual == expected, actual
    assert torch.version.cuda == '13.0'
    assert torch.cuda.is_available()
    assert torch.backends.cuda.matmul.allow_fp16_accumulation
    backend = ck.list_backends()['cuda']
    assert backend['available'] and not backend['disabled'], backend
    torch.manual_seed(42)
    torch.cuda.synchronize()
    started = perf_counter()
    x = torch.randn(64, 64, device='cuda', dtype=torch.float16)
    y = x @ x.T
    assert torch.isfinite(y).all()
    torch.cuda.synchronize()
    matmul_seconds = perf_counter() - started

    boxes = torch.tensor([[0, 0, 2, 2], [0, 0, 2, 2]], device='cuda', dtype=torch.float32)
    scores = torch.tensor([0.9, 0.8], device='cuda')
    assert torchvision.ops.nms(boxes, scores, 0.5).tolist() == [0]
    waveform = torch.randn(1, 64, device='cuda')
    coefficients = torch.tensor([1.0, 0.0], device='cuda')
    filtered = torchaudio.functional.lfilter(waveform, coefficients, coefficients, clamp=False)
    torch.testing.assert_close(filtered, waveform)

    q, k, v = [torch.randn(1, 4, 128, 64, device='cuda', dtype=torch.float16) for _ in range(3)]
    started = perf_counter()
    attention = sageattn_qk_int8_pv_fp8_cuda(q, k, v, pv_accum_dtype='fp32+fp16')
    torch.cuda.synchronize()
    sage_seconds = perf_counter() - started
    reference = torch.nn.functional.scaled_dot_product_attention(q, k, v)
    assert attention.shape == q.shape and torch.isfinite(attention).all()
    torch.testing.assert_close(attention, reference, atol=0.035, rtol=0.1)

    x = torch.randn(1, 64, 5, 8, 8, device='cuda', dtype=torch.float16).contiguous(memory_format=torch.channels_last_3d)
    weight = torch.randn(64, 64, 3, 3, 3, device='cuda', dtype=torch.float16).contiguous(memory_format=torch.channels_last_3d) * 0.01
    scale = torch.ones((), device='cuda', dtype=torch.float32)
    started = perf_counter()
    with ck.use_backend('cuda'):
        quantized = ck.quantize_per_tensor_fp8(x.contiguous(), scale)
        restored = ck.dequantize_per_tensor_fp8(quantized, scale, output_type=torch.float16)
        convolution = ck.fp16_conv3d(x, weight)
    torch.cuda.synchronize()
    native_seconds = perf_counter() - started
    assert torch.isfinite(restored).all() and torch.isfinite(convolution).all()
    torch.testing.assert_close(restored, x, atol=0.13, rtol=0.07)
    torch.testing.assert_close(convolution, torch.nn.functional.conv3d(x, weight), atol=0.015, rtol=0.1)
    print(json.dumps({'versions': actual, 'cuda': torch.version.cuda, 'gpu': torch.cuda.get_device_name(),
                      'fp16_accumulation': torch.backends.cuda.matmul.allow_fp16_accumulation,
                      'native_cuda': True, 'sage_fp8pp': True, 'conv_shape': list(convolution.shape),
                      'torchvision_cuda_nms': True, 'torchaudio_cuda_lfilter': True,
                      'seconds': {'matmul': matmul_seconds, 'sage_fp8pp': sage_seconds, 'native_cuda': native_seconds},
                      'scope': 'Small CUDA smoke operations; no video generation benchmark.'}, indent=2))


if __name__ == '__main__':
    main()
