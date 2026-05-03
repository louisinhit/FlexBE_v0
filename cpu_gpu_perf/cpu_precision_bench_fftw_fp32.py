import argparse
import copy
import platform
import subprocess
import time
from functools import partial

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

try:
    import pyfftw
    PYFFTW_AVAILABLE = True
except Exception:
    pyfftw = None
    PYFFTW_AVAILABLE = False


Br = 8


def log_print(log_path, *args, sep=" ", end="\n", flush=False):
    msg = sep.join(str(a) for a in args) + end
    print(*args, sep=sep, end=end, flush=flush)
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(msg)


class FFTWBatchFFT:
    """
    FFTW complex64/FP32 FFT backend for tensors with shape [4, B, N].

    Fast path:
        Try a batched FFTW plan on the whole [4, B, N] array.

    Stable fallback:
        If batched planning fails on this pyFFTW/FFTW installation, use one
        reusable 1-D FFTW plan and loop over the [4 * B] vectors.

    Both paths are FFTW single precision because the arrays are complex64.
    """

    def __init__(
        self,
        batch_size,
        N,
        threads=1,
        flags=("FFTW_ESTIMATE",),
        log_path=None,
        force_loop=False,
    ):
        if not PYFFTW_AVAILABLE:
            raise RuntimeError("pyFFTW is not available. Install it with `pip install pyfftw` or `conda install -c conda-forge pyfftw`.")

        self.batch_size = batch_size
        self.N = N
        self.shape = (4, batch_size, N)
        self.threads = threads
        self.flags = flags
        self.mode = None

        self.fft_in = None
        self.fft_out = None
        self.fft_obj = None

        self.fft_in_1d = None
        self.fft_out_1d = None
        self.fft_obj_1d = None

        if not force_loop:
            try:
                self.fft_in = pyfftw.empty_aligned(self.shape, dtype="complex64")
                self.fft_out = pyfftw.empty_aligned(self.shape, dtype="complex64")
                self.fft_obj = pyfftw.FFTW(
                    self.fft_in,
                    self.fft_out,
                    axes=(2,),
                    direction="FFTW_FORWARD",
                    flags=flags,
                    threads=threads,
                )
                self.mode = "batched"
                if log_path is not None:
                    log_print(
                        log_path,
                        f"[FFTW] batched complex64 plan created: shape={self.shape}, axes=(2,), threads={threads}, flags={flags}",
                    )
            except Exception as e:
                if log_path is not None:
                    log_print(log_path, f"[FFTW WARNING] batched plan unavailable: {repr(e)}")
                    log_print(log_path, "[FFTW] using stable reusable 1-D complex64 plan instead")
                self._make_loop_plan(log_path)
        else:
            if log_path is not None:
                log_print(log_path, "[FFTW] force_loop=True; using reusable 1-D complex64 plan")
            self._make_loop_plan(log_path)

    def _make_loop_plan(self, log_path=None):
        self.fft_in_1d = pyfftw.empty_aligned((self.N,), dtype="complex64")
        self.fft_out_1d = pyfftw.empty_aligned((self.N,), dtype="complex64")
        self.fft_obj_1d = pyfftw.FFTW(
            self.fft_in_1d,
            self.fft_out_1d,
            axes=(0,),
            direction="FFTW_FORWARD",
            flags=self.flags,
            threads=self.threads,
        )
        self.mode = "loop_1d"
        if log_path is not None:
            log_print(
                log_path,
                f"[FFTW] 1-D complex64 loop plan created: N={self.N}, threads={self.threads}, flags={self.flags}",
            )

    def __call__(self, x_torch):
        assert x_torch.device.type == "cpu"
        assert x_torch.dtype == torch.complex64
        assert tuple(x_torch.shape) == self.shape

        x_np = x_torch.detach().contiguous().numpy()

        if self.mode == "batched":
            self.fft_in[:] = x_np
            self.fft_obj()
            return torch.from_numpy(self.fft_out.copy())

        # Stable fallback: apply one 1-D FFTW plan over [4 * B] vectors.
        out_np = np.empty(self.shape, dtype=np.complex64)
        for i in range(4):
            for b in range(self.batch_size):
                self.fft_in_1d[:] = x_np[i, b, :]
                self.fft_obj_1d()
                out_np[i, b, :] = self.fft_out_1d
        return torch.from_numpy(out_np)


class BUModelCPU(nn.Module):
    """
    CPU benchmark model.

    fft_backend:
      - "torch": torch.fft.fft, complex64 input/output.
      - "fftw" : pyFFTW/FFTW complex64 single-precision FFT.

    nn_dtype:
      - torch.float32 or torch.float16.

    No autocast and no fake quantization are used.
    """

    def __init__(
        self,
        N,
        l,
        ch,
        mpexp,
        batch_size,
        fft_backend="torch",
        nn_dtype=torch.float32,
        fftw_threads=1,
        fftw_flags=("FFTW_ESTIMATE",),
        force_fftw_loop=False,
        log_path=None,
    ):
        super().__init__()
        assert fft_backend in ["torch", "fftw"]

        self.N = N
        self.l = l
        self.ch = ch
        self.mpexp = mpexp
        self.batch_size = batch_size
        self.fft_backend = fft_backend
        self.nn_dtype = nn_dtype

        self.torch_fft = partial(torch.fft.fft, dim=-1)

        self.fftw = None
        if fft_backend == "fftw":
            self.fftw = FFTWBatchFFT(
                batch_size=batch_size,
                N=N,
                threads=fftw_threads,
                flags=fftw_flags,
                log_path=log_path,
                force_loop=force_fftw_loop,
            )

        for idx in range(7):
            setattr(self, f"lin_{idx}", nn.Linear(self.l, self.l))

        self.flat = nn.Flatten()

    @property
    def fftw_mode(self):
        return self.fftw.mode if self.fftw is not None else "N/A"

    def _fft(self, fft_inputs):
        if self.fft_backend == "torch":
            return self.torch_fft(fft_inputs)
        return self.fftw(fft_inputs)

    def forward(self, x):
        B = x.shape[0]

        # FFT frontend: complex64/FP32 complex path.
        X0 = x
        X2 = x * x
        X4 = X2 * X2
        X6 = X2 * x

        fft_inputs = torch.stack([X0, X2, X4, X6], dim=0).contiguous()
        fft_outputs = self._fft(fft_inputs)

        X1 = fft_outputs[0]
        X3 = fft_outputs[1]
        X5 = fft_outputs[2]
        X7 = fft_outputs[3]

        X = torch.stack([X0, X2, X4, X6, X1, X3, X5, X7], dim=0)
        X = torch.abs(X)              # complex64 -> float32
        X = X.to(self.nn_dtype)       # strict NN dtype boundary

        result = []
        for br in range(Br):
            x_br = X[br, :, :]
            x_br = x_br.reshape(B, self.N // self.ch, self.ch).repeat(
                1, 1, self.l // self.ch
            )

            x_br = self.lin_0(x_br)
            x_br = F.relu(x_br)

            x_br = x_br.transpose(1, 2)
            x_br = F.max_pool1d(
                x_br, kernel_size=self.mpexp, stride=self.mpexp
            ).permute(0, 2, 1)

            y = self.lin_1(x_br)
            y = F.relu(y)
            y = self.lin_2(y)
            y = y + x_br

            y = y.permute(0, 2, 1)
            x_br = F.relu(y)
            x_br = F.max_pool1d(x_br, kernel_size=8, stride=8).permute(0, 2, 1)

            y = self.lin_3(x_br)
            y = F.relu(y)
            y = self.lin_4(y)
            y = y + x_br

            y = y.permute(0, 2, 1)
            x_br = F.relu(y)
            x_br = F.max_pool1d(x_br, kernel_size=8, stride=8).permute(0, 2, 1)

            y = self.lin_5(x_br)
            y = F.relu(y)
            y = self.lin_6(y)
            y = y + x_br

            y = y.permute(0, 2, 1)
            x_br = F.relu(y)
            x_br = F.max_pool1d(x_br, kernel_size=4, stride=4).permute(0, 2, 1)

            result.append(self.flat(x_br))

        return result


def make_complex64_input(batch_size, N):
    return torch.randn(batch_size, N, dtype=torch.complex64, device="cpu")


def dtype_probe(model, x):
    model.eval()
    with torch.inference_mode():
        X0 = x
        X2 = x * x
        X4 = X2 * X2
        X6 = X2 * x

        fft_inputs = torch.stack([X0, X2, X4, X6], dim=0).contiguous()
        fft_outputs = model._fft(fft_inputs)

        X = torch.stack(
            [X0, X2, X4, X6, fft_outputs[0], fft_outputs[1], fft_outputs[2], fft_outputs[3]],
            dim=0,
        )
        X_abs = torch.abs(X)
        X_nn = X_abs.to(model.nn_dtype)
        out = model(x)

        return {
            "input_dtype": x.dtype,
            "input_real_dtype": x.real.dtype,
            "fft_backend": model.fft_backend,
            "fftw_mode": model.fftw_mode,
            "fft_inputs_dtype": fft_inputs.dtype,
            "fft_outputs_dtype": fft_outputs.dtype,
            "abs_output_dtype": X_abs.dtype,
            "nn_input_dtype": X_nn.dtype,
            "lin_0_weight_dtype": model.lin_0.weight.dtype,
            "lin_0_bias_dtype": model.lin_0.bias.dtype,
            "output_0_dtype": out[0].dtype,
        }


def log_dtype_probe(log_path, case_name, model, x):
    info = dtype_probe(model, x)
    log_print(log_path, f"[DTYPE PROBE] {case_name}")
    for k, v in info.items():
        log_print(log_path, f"  {k:<22}: {v}")
    log_print(log_path, "")


def log_cpu_info(log_path):
    log_print(log_path, "[CPU / SOFTWARE INFO]")
    log_print(log_path, f"  platform          : {platform.platform()}")
    log_print(log_path, f"  processor         : {platform.processor()}")
    log_print(log_path, f"  torch version     : {torch.__version__}")
    log_print(log_path, f"  numpy version     : {np.__version__}")
    log_print(log_path, f"  pyfftw available  : {PYFFTW_AVAILABLE}")
    if PYFFTW_AVAILABLE:
        log_print(log_path, f"  pyfftw version    : {getattr(pyfftw, '__version__', 'unknown')}")
    log_print(log_path, f"  mkldnn enabled    : {torch.backends.mkldnn.enabled}")
    log_print(log_path, f"  torch num threads : {torch.get_num_threads()}")
    log_print(log_path, f"  interop threads   : {torch.get_num_interop_threads()}")
    try:
        log_print(log_path, f"  cpu capability    : {torch._C._get_cpu_capability()}")
    except Exception as e:
        log_print(log_path, f"  cpu capability    : N/A ({repr(e)})")

    try:
        out = subprocess.check_output(
            "lscpu | egrep 'Model name|Flags|avx512_bf16|amx_bf16|amx_tile|avx512_fp16|f16c'",
            shell=True,
            stderr=subprocess.STDOUT,
            text=True,
        )
        log_print(log_path, "\n[lscpu relevant lines]")
        log_print(log_path, out)
    except Exception as e:
        log_print(log_path, f"  lscpu probe failed: {repr(e)}")
    log_print(log_path, "")


def benchmark_case(
    case_name,
    model,
    batch_size,
    N,
    test_round,
    warmup,
    log_path,
):
    try:
        model.eval()
        log_print(log_path, "\n" + "-" * 80)
        log_print(log_path, f"Running case : {case_name}")
        log_print(log_path, "Device       : CPU")
        log_print(log_path, f"Batch size   : {batch_size}")
        log_print(log_path, f"FFT backend  : {model.fft_backend}")
        log_print(log_path, f"FFTW mode    : {model.fftw_mode}")
        log_print(log_path, f"NN dtype     : {model.nn_dtype}")
        log_print(log_path, "-" * 80)

        x = make_complex64_input(batch_size, N)
        log_dtype_probe(log_path, case_name, model, x)

        with torch.inference_mode():
            for _ in range(warmup):
                x = make_complex64_input(batch_size, N)
                _ = model(x)

        timings = []
        with torch.inference_mode():
            for _ in range(test_round):
                x = make_complex64_input(batch_size, N)
                t0 = time.perf_counter()
                _ = model(x)
                t1 = time.perf_counter()
                timings.append(t1 - t0)

        if len(timings) > 1:
            timings = timings[1:]

        avg_t = sum(timings) / len(timings)
        throughput = batch_size / avg_t

        log_print(log_path, f"[OK] {case_name}")
        log_print(log_path, f"  avg latency : {avg_t:.8f} s")
        log_print(log_path, f"  throughput  : {throughput:.4f} samples/s")
        log_print(log_path, f"  timings[:10]: {timings[:10]} ...")

        return {
            "case": case_name,
            "status": "OK",
            "avg_sec": avg_t,
            "throughput_samples_per_sec": throughput,
            "timings": timings,
        }

    except Exception as e:
        log_print(log_path, f"[FAIL] {case_name}")
        log_print(log_path, f"  reason: {repr(e)}")
        return {
            "case": case_name,
            "status": "FAIL",
            "avg_sec": None,
            "throughput_samples_per_sec": None,
            "timings": None,
            "error": repr(e),
        }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", type=int, default=1)
    parser.add_argument("--log", type=str, default="cpu_precision_bench_fftw_fp32_log.txt")
    parser.add_argument("--torch_threads", type=int, default=0)
    parser.add_argument("--fftw_threads", type=int, default=1)
    parser.add_argument("--rounds", type=int, default=100)
    parser.add_argument("--warmup", type=int, default=10)
    parser.add_argument("--force_fftw_loop", action="store_true")
    args = parser.parse_args()

    if args.torch_threads > 0:
        torch.set_num_threads(args.torch_threads)

    N = 32768
    l = 32
    mpexp = 4
    ch = 8

    batch_size = args.batch
    log_path = args.log

    log_print(log_path, "\n" + "=" * 100)
    log_print(log_path, "CPU strict precision benchmark: FP32 baseline + torch FP32FFT/FP16NN + FFTW FP32FFT/FP32NN")
    log_print(log_path, f"batch_size    : {batch_size}")
    log_print(log_path, f"rounds        : {args.rounds}")
    log_print(log_path, f"warmup        : {args.warmup}")
    log_print(log_path, f"torch threads : {torch.get_num_threads()}")
    log_print(log_path, f"fftw threads  : {args.fftw_threads}")
    log_print(log_path, f"force fftw loop: {args.force_fftw_loop}")
    log_print(log_path, "=" * 100)

    log_cpu_info(log_path)

    results = []

    # 1) All FP32 PyTorch CPU baseline.
    model_torch_fp32 = BUModelCPU(
        N=N,
        l=l,
        ch=ch,
        mpexp=mpexp,
        batch_size=batch_size,
        fft_backend="torch",
        nn_dtype=torch.float32,
    ).to(torch.float32)

    results.append(
        benchmark_case(
            "CPU_TORCHFFT_FP32FFT_FP32NN_strict",
            model_torch_fp32,
            batch_size,
            N,
            args.rounds,
            args.warmup,
            log_path,
        )
    )

    # 2) PyTorch CPU FFT FP32 + NN FP16.
    model_torch_fp16nn = BUModelCPU(
        N=N,
        l=l,
        ch=ch,
        mpexp=mpexp,
        batch_size=batch_size,
        fft_backend="torch",
        nn_dtype=torch.float16,
    ).to(torch.float16)

    results.append(
        benchmark_case(
            "CPU_TORCHFFT_FP32FFT_FP16NN_strict",
            model_torch_fp16nn,
            batch_size,
            N,
            args.rounds,
            args.warmup,
            log_path,
        )
    )

    # 3) FFTW CPU FFT FP32/complex64 + NN FP32.
    model_fftw_fp32 = BUModelCPU(
        N=N,
        l=l,
        ch=ch,
        mpexp=mpexp,
        batch_size=batch_size,
        fft_backend="fftw",
        nn_dtype=torch.float32,
        fftw_threads=args.fftw_threads,
        fftw_flags=("FFTW_ESTIMATE",),
        force_fftw_loop=args.force_fftw_loop,
        log_path=log_path,
    ).to(torch.float32)

    results.append(
        benchmark_case(
            "CPU_FFTWFFT_FP32FFT_FP32NN_strict",
            model_fftw_fp32,
            batch_size,
            N,
            args.rounds,
            args.warmup,
            log_path,
        )
    )

    log_print(log_path, "\n================ SUMMARY ================")
    for r in results:
        if r["status"] == "OK":
            log_print(
                log_path,
                f'{r["case"]}: latency={r["avg_sec"]:.8f} s, throughput={r["throughput_samples_per_sec"]:.4f} samples/s',
            )
        else:
            log_print(log_path, f'{r["case"]}: N/A ({r["error"]})')


if __name__ == "__main__":
    main()
