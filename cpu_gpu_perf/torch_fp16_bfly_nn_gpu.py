import torch
import torch.nn as nn
import torch.nn.functional as F

import argparse
import copy
from functools import partial


Br = 8


def log_print(log_path, *args, sep=" ", end="\n", flush=False):
    msg = sep.join(str(a) for a in args) + end
    print(*args, sep=sep, end=end, flush=flush)
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(msg)


class BU_Model_Strict(nn.Module):
    """
    Strict precision benchmark model.

    mode:
      - "fp16_all":
          FFT path: chalf / complex32
          NN path : float16

      - "fp16fft_bf16nn":
          FFT path: chalf / complex32
          NN path : bfloat16 after abs()
    """

    def __init__(self, N, l, ch, mpexp, mode="fp16_all"):
        super().__init__()

        assert mode in ["fp16_all", "fp16fft_bf16nn"]

        self.N = N
        self.l = l
        self.ch = ch
        self.mpexp = mpexp
        self.mode = mode

        self.fft = partial(torch.fft.fft, dim=-1)

        for idx in range(7):
            setattr(self, f"lin_{idx}", nn.Linear(self.l, self.l))

        self.flat = nn.Flatten()

    def _to_nn_dtype(self, x):
        if self.mode == "fp16_all":
            return x.to(torch.float16)

        if self.mode == "fp16fft_bf16nn":
            return x.to(torch.bfloat16)

        raise RuntimeError(f"Unknown mode: {self.mode}")

    def forward(self, x):
        B = x.shape[0]

        # -------------------------------------------------------
        # FFT section.
        # x is expected to be torch.chalf / complex32.
        # Use multiplication instead of torch.pow for stricter dtype behaviour.
        # -------------------------------------------------------
        X0 = x
        X2 = x * x
        X4 = X2 * X2
        X6 = X2 * x

        fft_inputs = torch.stack([X0, X2, X4, X6], dim=0)
        fft_outputs = self.fft(fft_inputs)

        X1 = fft_outputs[0]
        X3 = fft_outputs[1]
        X5 = fft_outputs[2]
        X7 = fft_outputs[3]

        X = torch.stack([X0, X2, X4, X6, X1, X3, X5, X7], dim=0)

        # abs(chalf) -> real half in the FP16 FFT path.
        X = torch.abs(X)

        # -------------------------------------------------------
        # NN section.
        # For "fp16_all": keep as float16.
        # For "fp16fft_bf16nn": convert the real feature tensor to bf16.
        # -------------------------------------------------------
        X = self._to_nn_dtype(X)

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
                x_br,
                kernel_size=self.mpexp,
                stride=self.mpexp
            ).permute(0, 2, 1)

            y = self.lin_1(x_br)
            y = F.relu(y)
            y = self.lin_2(y)
            y = y + x_br

            y = y.permute(0, 2, 1)
            x_br = F.relu(y)
            x_br = F.max_pool1d(
                x_br,
                kernel_size=8,
                stride=8
            ).permute(0, 2, 1)

            y = self.lin_3(x_br)
            y = F.relu(y)
            y = self.lin_4(y)
            y = y + x_br

            y = y.permute(0, 2, 1)
            x_br = F.relu(y)
            x_br = F.max_pool1d(
                x_br,
                kernel_size=8,
                stride=8
            ).permute(0, 2, 1)

            y = self.lin_5(x_br)
            y = F.relu(y)
            y = self.lin_6(y)
            y = y + x_br

            y = y.permute(0, 2, 1)
            x_br = F.relu(y)
            x_br = F.max_pool1d(
                x_br,
                kernel_size=4,
                stride=4
            ).permute(0, 2, 1)

            result.append(self.flat(x_br))

        return result


def make_complex_fp16_input(batch_size, N, device):
    """
    Strict FP16 complex input:
      real: float16
      imag: float16
      complex: torch.chalf / complex32
    """
    real = torch.randn(batch_size, N, dtype=torch.float16, device=device)
    imag = torch.randn(batch_size, N, dtype=torch.float16, device=device)
    return torch.complex(real, imag)


def check_model_param_dtype(model):
    dtypes = {}
    for name, param in model.named_parameters():
        dtypes[name] = param.dtype
    return dtypes


def dtype_probe(model, x):
    """
    A manual dtype probe for the major boundaries:
      - input
      - FFT input/output
      - abs output
      - NN input
      - first linear weight
      - final output
    """
    model.eval()

    with torch.inference_mode():
        B = x.shape[0]

        X0 = x
        X2 = x * x
        X4 = X2 * X2
        X6 = X2 * x

        fft_inputs = torch.stack([X0, X2, X4, X6], dim=0)
        fft_outputs = model.fft(fft_inputs)

        X1 = fft_outputs[0]
        X3 = fft_outputs[1]
        X5 = fft_outputs[2]
        X7 = fft_outputs[3]

        X = torch.stack([X0, X2, X4, X6, X1, X3, X5, X7], dim=0)
        X_abs = torch.abs(X)
        X_nn = model._to_nn_dtype(X_abs)

        out = model(x)

        info = {
            "input_dtype": x.dtype,
            "input_real_dtype": x.real.dtype,
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


def benchmark_gpu_case(
    case_name,
    base_model,
    device,
    batch_size,
    N,
    model_dtype,
    test_round=100,
    warmup=20,
    log_path="strict_gpu_precision_log.txt",
):
    try:
        model = copy.deepcopy(base_model).to(device)
        model = model.to(model_dtype)
        model.eval()

        log_print(log_path, "\n" + "-" * 70)
        log_print(log_path, f"Running case: {case_name}")
        log_print(log_path, f"Device      : {device}")
        log_print(log_path, f"GPU name    : {torch.cuda.get_device_name(device)}")
        log_print(log_path, f"Batch size  : {batch_size}")
        log_print(log_path, f"Model dtype : {model_dtype}")
        log_print(log_path, "-" * 70)

        # Dtype check
        with torch.inference_mode():
            x = make_complex_fp16_input(batch_size, N, device)
            log_dtype_probe(log_path, case_name, model, x)

        # Warmup
        with torch.inference_mode():
            for _ in range(warmup):
                x = make_complex_fp16_input(batch_size, N, device)
                _ = model(x)

        torch.cuda.synchronize()

        timings = []

        with torch.inference_mode():
            for _ in range(test_round):
                x = make_complex_fp16_input(batch_size, N, device)

                start_event = torch.cuda.Event(enable_timing=True)
                end_event = torch.cuda.Event(enable_timing=True)

                start_event.record()
                _ = model(x)
                end_event.record()

                torch.cuda.synchronize()
                elapsed_s = start_event.elapsed_time(end_event) / 1000.0
                timings.append(elapsed_s)

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


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", type=int, default=1)
    parser.add_argument("--gpu", type=int, default=0)
    parser.add_argument("--log", type=str, default="strict_gpu_precision_log.txt")
    args = parser.parse_args()

    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is not available. This script requires GPU.")

    # Keep this benchmark strict. No TF32 contamination.
    # TF32 is for FP32 matmul/convolution acceleration, not desired here.
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False

    N = 32768
    l = 32
    mpexp = 4
    ch = 8

    batch_size = args.batch
    device = torch.device(f"cuda:{args.gpu}")
    log_path = args.log

    test_round = 100
    warmup = 10

    log_print(log_path, "\n" + "=" * 80)
    log_print(log_path, "Strict GPU precision benchmark without autocast")
    log_print(log_path, f"batch_size              : {batch_size}")
    log_print(log_path, f"device                  : {device}")
    log_print(log_path, f"gpu name                : {torch.cuda.get_device_name(device)}")
    log_print(log_path, f"TF32 matmul allowed     : {torch.backends.cuda.matmul.allow_tf32}")
    log_print(log_path, f"TF32 cudnn allowed      : {torch.backends.cudnn.allow_tf32}")
    log_print(log_path, "=" * 80)

    results = []

    # ------------------------------------------------------------
    # Case 1:
    # All FP16 strict.
    #
    # FFT:
    #   input real/imag float16 -> complex chalf
    #   torch.fft.fft on chalf
    #
    # NN:
    #   parameters float16
    #   activations float16
    #   outputs float16
    #
    # No autocast.
    # ------------------------------------------------------------
    base_fp16 = BU_Model_Strict(
        N=N,
        l=l,
        ch=ch,
        mpexp=mpexp,
        mode="fp16_all",
    )

    results.append(
        benchmark_gpu_case(
            case_name="GPU_FP16_all_strict",
            base_model=base_fp16,
            device=device,
            batch_size=batch_size,
            N=N,
            model_dtype=torch.float16,
            test_round=test_round,
            warmup=warmup,
            log_path=log_path,
        )
    )

    # ------------------------------------------------------------
    # Case 2:
    # FFT FP16 + NN BF16 strict.
    #
    # FFT:
    #   input real/imag float16 -> complex chalf
    #   torch.fft.fft on chalf
    #
    # Boundary:
    #   abs(chalf) -> float16
    #   then explicitly convert feature tensor to bfloat16
    #
    # NN:
    #   parameters bfloat16
    #   activations bfloat16
    #   outputs bfloat16
    #
    # No autocast.
    # ------------------------------------------------------------
    base_fp16fft_bf16nn = BU_Model_Strict(
        N=N,
        l=l,
        ch=ch,
        mpexp=mpexp,
        mode="fp16fft_bf16nn",
    )

    results.append(
        benchmark_gpu_case(
            case_name="GPU_FP16FFT_BF16NN_strict",
            base_model=base_fp16fft_bf16nn,
            device=device,
            batch_size=batch_size,
            N=N,
            model_dtype=torch.bfloat16,
            test_round=test_round,
            warmup=warmup,
            log_path=log_path,
        )
    )

    log_print(log_path, "\n================ SUMMARY ================ ")
    for r in results:
        if r["status"] == "OK":
            log_print(
                log_path,
                f'{r["case"]}: '
                f'latency={r["avg_sec"]:.8f} s, '
                f'throughput={r["throughput_samples_per_sec"]:.4f} samples/s'
            )
        else:
            log_print(log_path, f'{r["case"]}: N/A ({r["error"]})')
