import argparse
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


class SafeFFTWBatchFFT:
    """
    Robust pyFFTW wrapper for batched complex64 FFT along the last dimension.

    It first tries a real batched pyFFTW plan over shape [4, B, N].
    If the planner returns NULL on a given machine/build, it falls back to a
    conservative 1-D FFTW plan and loops over the leading dimensions.

    Both paths use FFTW single precision because the numpy/pyFFTW dtype is
    complex64. No FP16/BF16 FFT is claimed here.
    """

    def __init__(self, shape, threads=1, log_path="cpu_precision_bench_log.txt"):
        if not PYFFTW_AVAILABLE:
            raise RuntimeError("pyfftw is not available. Install it with: conda install -c conda-forge pyfftw")

        self.shape = tuple(shape)
        self.N = self.shape[-1]
        self.threads = max(int(threads), 1)
        self.log_path = log_path
        self.mode = None
        self.plan_error = None

        # Prefer FFTW_ESTIMATE here. It is less aggressive than MEASURE and is
        # much less likely to hit planner/library corner cases.
        # Use an explicit positive axis instead of -1.
        try:
            self.fft_in = pyfftw.empty_aligned(self.shape, dtype="complex64")
            self.fft_out = pyfftw.empty_aligned(self.shape, dtype="complex64")
            self.plan = pyfftw.FFTW(
                self.fft_in,
                self.fft_out,
                axes=(len(self.shape) - 1,),
                direction="FFTW_FORWARD",
                flags=("FFTW_ESTIMATE",),
                threads=self.threads,
            )
            self.mode = "batched"
            log_print(self.log_path, f"[FFTW] batched plan created: shape={self.shape}, threads={self.threads}, flags=FFTW_ESTIMATE")
        except Exception as e:
            self.plan_error = repr(e)
            log_print(self.log_path, f"[FFTW] batched plan failed: {self.plan_error}")
            log_print(self.log_path, "[FFTW] falling back to safe 1-D loop plan")

            # Conservative fallback: one 1-D plan over N, then loop over [4*B].
            # This avoids multi-dimensional planner bugs and still uses FFTW.
            self.fft_in_1d = pyfftw.empty_aligned((self.N,), dtype="complex64")
            self.fft_out_1d = pyfftw.empty_aligned((self.N,), dtype="complex64")
            self.plan_1d = pyfftw.FFTW(
                self.fft_in_1d,
                self.fft_out_1d,
                axes=(0,),
                direction="FFTW_FORWARD",
                flags=("FFTW_ESTIMATE",),
                threads=self.threads,
            )
            self.mode = "loop_1d"
            log_print(self.log_path, f"[FFTW] 1-D loop plan created: N={self.N}, threads={self.threads}, flags=FFTW_ESTIMATE")

    def __call__(self, x_torch: torch.Tensor) -> torch.Tensor:
        assert x_torch.device.type == "cpu"
        assert x_torch.dtype == torch.complex64
        assert tuple(x_torch.shape) == self.shape

        x_np = x_torch.detach().contiguous().numpy()

        if self.mode == "batched":
            self.fft_in[...] = x_np
            self.plan()
            return torch.from_numpy(self.fft_out.copy())

        if self.mode == "loop_1d":
            out_np = np.empty_like(x_np)
            flat_in = x_np.reshape(-1, self.N)
            flat_out = out_np.reshape(-1, self.N)
            for i in range(flat_in.shape[0]):
                self.fft_in_1d[:] = flat_in[i]
                self.plan_1d()
                flat_out[i, :] = self.fft_out_1d
            return torch.from_numpy(out_np)

        raise RuntimeError(f"Unknown FFTW mode: {self.mode}")


class BUModelCPU(nn.Module):
    def __init__(self, N, l, ch, mpexp, batch_size, fft_backend="torch", nn_dtype=torch.float16,
                 fftw_threads=1, log_path="cpu_precision_bench_log.txt"):
        super().__init__()

        assert fft_backend in ["torch", "fftw"]
        assert nn_dtype in [torch.float16, torch.bfloat16, torch.float32]

        self.N = N
        self.l = l
        self.ch = ch
        self.mpexp = mpexp
        self.batch_size = batch_size
        self.fft_backend = fft_backend
        self.nn_dtype = nn_dtype
        self.log_path = log_path

        self.torch_fft = partial(torch.fft.fft, dim=-1)
        self.fftw = None
        if fft_backend == "fftw":
            self.fftw = SafeFFTWBatchFFT(
                shape=(4, batch_size, N),
                threads=fftw_threads,
                log_path=log_path,
            )

        for idx in range(7):
            setattr(self, f"lin_{idx}", nn.Linear(self.l, self.l))

        self.flat = nn.Flatten()

    def fft_forward(self, fft_inputs):
        if self.fft_backend == "torch":
            return self.torch_fft(fft_inputs)
        return self.fftw(fft_inputs)

    def _to_nn_dtype(self, x):
        return x.to(self.nn_dtype)

    def forward(self, x):
        B = x.shape[0]
        if B != self.batch_size:
            raise RuntimeError(f"This model was built for batch_size={self.batch_size}, but got B={B}")

        # FFT front-end: complex64 / FP32 real-imag.
        X0 = x
        X2 = x * x
        X4 = X2 * X2
        X6 = X2 * x

        fft_inputs = torch.stack([X0, X2, X4, X6], dim=0).contiguous()
        fft_outputs = self.fft_forward(fft_inputs)

        X1 = fft_outputs[0]
        X3 = fft_outputs[1]
        X5 = fft_outputs[2]
        X7 = fft_outputs[3]

        X = torch.stack([X0, X2, X4, X6, X1, X3, X5, X7], dim=0)
        X = torch.abs(X)            # complex64 -> float32
        X = self._to_nn_dtype(X)    # strict NN dtype boundary

        result = []
        for br in range(Br):
            x_br = X[br, :, :]

            x_br = x_br.reshape(B, self.N // self.ch, self.ch).repeat(
                1, 1, self.l // self.ch
            )

            x_br = self.lin_0(x_br)
            x_br = F.relu(x_br)

            x_br = x_br.transpose(1, 2)
            x_br = F.max_pool1d(x_br, kernel_size=self.mpexp, stride=self.mpexp).permute(0, 2, 1)

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
    with torch.inference_mode():
        X0 = x
        X2 = x * x
        X4 = X2 * X2
        X6 = X2 * x

        fft_inputs = torch.stack([X0, X2, X4, X6], dim=0).contiguous()
        fft_outputs = model.fft_forward(fft_inputs)

        X1, X3, X5, X7 = fft_outputs[0], fft_outputs[1], fft_outputs[2], fft_outputs[3]
        X = torch.stack([X0, X2, X4, X6, X1, X3, X5, X7], dim=0)
        X_abs = torch.abs(X)
        X_nn = model._to_nn_dtype(X_abs)
        out = model(x)

        info = {
            "input_dtype": x.dtype,
            "input_real_dtype": x.real.dtype,
            "fft_backend": model.fft_backend,
            "fftw_mode": getattr(model.fftw, "mode", "N/A") if model.fftw is not None else "N/A",
            "fft_inputs_dtype": fft_inputs.dtype,
            "fft_outputs_dtype": fft_outputs.dtype,
            "abs_output_dtype": X_abs.dtype,
            "nn_input_dtype": X_nn.dtype,
            "lin_0_weight_dtype": model.lin_0.weight.dtype,
            "lin_0_bias_dtype": model.lin_0.bias.dtype,
            "output_0_dtype": out[0].dtype,
        }
    return info


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
        try:
            log_print(log_path, f"  pyfftw version    : {pyfftw.__version__}")
        except Exception:
            pass
    log_print(log_path, f"  mkldnn enabled    : {torch.backends.mkldnn.enabled}")
    log_print(log_path, f"  torch num threads : {torch.get_num_threads()}")
    log_print(log_path, f"  interop threads   : {torch.get_num_interop_threads()}")
    try:
        log_print(log_path, f"  cpu capability    : {torch._C._get_cpu_capability()}")
    except Exception as e:
        log_print(log_path, f"  cpu capability    : N/A ({repr(e)})")

    try:
        out = subprocess.check_output(
            "lscpu | egrep 'Model name|Flags|avx512_bf16|amx_bf16|amx_tile|f16c|avx2'",
            shell=True,
            stderr=subprocess.STDOUT,
            text=True,
        )
        log_print(log_path, "\n[lscpu relevant lines]")
        log_print(log_path, out)
    except Exception as e:
        log_print(log_path, f"  lscpu probe failed: {repr(e)}")
    log_print(log_path, "")


def build_model(case_name, N, l, ch, mpexp, batch_size, fftw_threads, log_path):
    if case_name == "CPU_TORCHFFT_FP32FFT_FP16NN_strict":
        model = BUModelCPU(
            N=N, l=l, ch=ch, mpexp=mpexp, batch_size=batch_size,
            fft_backend="torch", nn_dtype=torch.float16,
            fftw_threads=fftw_threads, log_path=log_path,
        )
        model = model.to(torch.float16)
        return model

    if case_name == "CPU_FFTWFFT_FP32FFT_BF16NN_strict":
        model = BUModelCPU(
            N=N, l=l, ch=ch, mpexp=mpexp, batch_size=batch_size,
            fft_backend="fftw", nn_dtype=torch.bfloat16,
            fftw_threads=fftw_threads, log_path=log_path,
        )
        model = model.to(torch.bfloat16)
        return model

    raise ValueError(f"Unknown case: {case_name}")


def benchmark_case(case_name, N, l, ch, mpexp, batch_size, fftw_threads, rounds, warmup, log_path):
    try:
        model = build_model(case_name, N, l, ch, mpexp, batch_size, fftw_threads, log_path)
        model.eval()

        log_print(log_path, "\n" + "-" * 80)
        log_print(log_path, f"Running case : {case_name}")
        log_print(log_path, "Device       : CPU")
        log_print(log_path, f"Batch size   : {batch_size}")
        log_print(log_path, f"FFT backend  : {model.fft_backend}")
        log_print(log_path, f"FFTW mode    : {getattr(model.fftw, 'mode', 'N/A') if model.fftw is not None else 'N/A'}")
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
            for _ in range(rounds):
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
    parser.add_argument("--log", type=str, default="cpu_precision_bench_log.txt")
    parser.add_argument("--torch-threads", type=int, default=0)
    parser.add_argument("--fftw-threads", type=int, default=1)
    parser.add_argument("--rounds", type=int, default=100)
    parser.add_argument("--warmup", type=int, default=10)
    args = parser.parse_args()

    if args.torch_threads > 0:
        torch.set_num_threads(args.torch_threads)

    N = 32768
    l = 32
    mpexp = 4
    ch = 8

    log_path = args.log

    log_print(log_path, "\n" + "=" * 100)
    log_print(log_path, "CPU strict precision benchmark: torch FFT FP32 + FP16 NN vs FFTW FP32 + BF16 NN")
    log_print(log_path, f"batch_size    : {args.batch}")
    log_print(log_path, f"rounds        : {args.rounds}")
    log_print(log_path, f"warmup        : {args.warmup}")
    log_print(log_path, f"torch threads : {torch.get_num_threads()}")
    log_print(log_path, f"fftw threads  : {args.fftw_threads}")
    log_print(log_path, "=" * 100)

    log_cpu_info(log_path)

    results = []
    for case_name in [
        "CPU_TORCHFFT_FP32FFT_FP16NN_strict",
        "CPU_FFTWFFT_FP32FFT_BF16NN_strict",
    ]:
        results.append(
            benchmark_case(
                case_name=case_name,
                N=N,
                l=l,
                ch=ch,
                mpexp=mpexp,
                batch_size=args.batch,
                fftw_threads=args.fftw_threads,
                rounds=args.rounds,
                warmup=args.warmup,
                log_path=log_path,
            )
        )

    log_print(log_path, "\n================ SUMMARY ================")
    for r in results:
        if r["status"] == "OK":
            log_print(
                log_path,
                f'{r["case"]}: latency={r["avg_sec"]:.8f} s, '
                f'throughput={r["throughput_samples_per_sec"]:.4f} samples/s'
            )
        else:
            log_print(log_path, f'{r["case"]}: N/A ({r["error"]})')


if __name__ == "__main__":
    main()
