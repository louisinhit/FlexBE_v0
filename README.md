# FlexBE

This repository contains the software and FPGA artifacts for **FlexBE**, a flexible FPGA butterfly engine for accelerating signal processing and machine-learning workloads.

The repository includes:

- CPU/GPU baseline scripts and result-processing notebooks.
- BSPNet model training code.
- Vivado RTL/IP/constraint files for FPGA synthesis and implementation.
- Reference Vivado reports used for the hardware results.

## Acknowledgement

This work builds on and is enabled by the open-source artifact repository:

- [os-hxfan/Butterfly_Acc](https://github.com/os-hxfan/Butterfly_Acc)

We thank the authors of `Butterfly_Acc` for releasing their hardware and evaluation artifacts, which provide an important basis for the development and comparison of this work.

## Repository Structure

```text
FlexBE_v0/
├── cpu_gpu_perf/      # CPU/GPU performance baselines and plotting notebooks
├── model/             # BSPNet model training and evaluation code
├── project_fb/        # Vivado FPGA project sources, IP, constraints, Tcl build flow, and reports
├── LICENSE
└── README.md
```

## CPU/GPU Performance Evaluation

The CPU and GPU implementations used in the paper are provided under:

```text
cpu_gpu_perf/
```

The shell scripts in this directory are used to reproduce the corresponding CPU/GPU baseline results. Typical entry points include:

```bash
cd cpu_gpu_perf

# CPU baseline experiments
bash test_cpu.sh

# GPU baseline experiments
bash test_gpu.sh

# CPU precision benchmark with FFTW/FP32
bash run_cpu_precision_bench_fftw_fp32.sh
```

The Jupyter notebook in this directory is used to process and visualise the performance results reported in the paper:

```text
cpu_gpu_perf/result_compare.ipynb
```

This notebook corresponds to the result analysis and plots associated with **Figure 11** and **Figure 15** in the paper.

The directory also includes log files and recorded power-measurement CSV files used for result checking and plotting.

## BSPNet Model Training

The BSPNet training and evaluation code is provided under:

```text
model/
```

This directory contains the model implementation, training scripts, and experiment logs used for BSPNet accuracy evaluation.

Typical contents include:

```text
model/
├── code_acc/    # BSPNet training/evaluation code
└── logs/        # Training and evaluation logs
```

Users should enter `model/code_acc/` and run the relevant training or evaluation scripts according to the experiment configuration.

## FPGA Implementation

The FPGA implementation is provided under:

```text
project_fb/
```

This directory contains the Vivado project sources for the FlexBE hardware design, including RTL files, Vivado IP cores, XDC constraints, Tcl build scripts, and reference implementation reports.

Typical contents include:

```text
project_fb/
├── build_project.tcl
├── sources_1/
│   ├── imports/design/   # Verilog/SystemVerilog RTL sources
│   └── ip/               # Vivado IP cores
├── constrs_1/new/        # XDC constraint files
└── vivado_rpt/           # Reference Vivado synthesis/implementation reports
```

The Vivado project can be rebuilt directly from the Tcl script. No `.xpr` project file is required in the repository.

From the repository root, run:

```bash
cd project_fb
vivado -mode batch -source build_project.tcl
```

To specify the number of parallel Vivado jobs:

```bash
vivado -mode batch -source build_project.tcl -tclargs 16
```

To run synthesis only without implementation:

```bash
vivado -mode batch -source build_project.tcl -tclargs 16 0
```

The full synthesis and implementation flow may take approximately **7--8 hours**, depending on the workstation, Vivado version, license availability, and the number of parallel jobs.

The `.rpt` files under `project_fb/vivado_rpt/` provide the reference Vivado synthesis and implementation reports corresponding to the hardware results reported in the paper.

For more detailed FPGA build instructions, see:

```text
project_fb/README.md
```

## Notes

- The repository does not include Vivado `.xpr` project files. The hardware project is reconstructed from the Tcl build script.
- Generated Vivado build directories, logs, and intermediate project files should not be committed.
- CPU/GPU results may vary across machines because of differences in CPU model, GPU model, CUDA version, PyTorch version, memory bandwidth, and system load.
- FPGA implementation runtime and timing results may vary slightly across Vivado versions and host machines.

## License

This repository is released under the license specified in `LICENSE`.
