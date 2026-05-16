# FlexBE Vivado Project Build

This directory contains the Vivado project sources for the FlexBE FPGA design. The project can be reconstructed directly from the provided Tcl script; no `.xpr` project file is required in the repository.

## Directory Layout

```text
project_fb/
├── build_project.tcl
├── sources_1/
│   ├── imports/design/   # Verilog/SystemVerilog RTL sources
│   └── ip/               # Vivado IP cores (.xci)
├── constrs_1/new/        # XDC constraint files
└── vivado_rpt/           # Reference reports
```

## Target Design

The build script is configured for the VCU128-based FlexBE design.

| Item | Setting |
|---|---|
| Top module | `bfly_acc_top_hbm` |
| Target board | Xilinx VCU128 |
| Target part | `xcvu37p-fsvh2892-2L-e` |
| Synthesis strategy | `Flow_PerfOptimized_high` |
| Implementation strategy | `Performance_ExploreWithRemap` |

## Prerequisites

Before running the build, make sure that:

1. AMD Vivado is installed and available from the command line.
2. The VCU128 board files are installed in Vivado.
3. This repository has been cloned locally.
4. `build_project.tcl` is placed in this directory:

```text
FlexBE_v0/project_fb/build_project.tcl
```

## Build the Project

From the repository root, enter the Vivado project directory:

```bash
cd FlexBE_v0/project_fb
```

Run the full build flow:

```bash
vivado -mode batch -source build_project.tcl
```

This command reconstructs the Vivado project, loads the RTL sources, IP cores, and XDC constraints, then runs synthesis and implementation.

## Specify the Number of Parallel Jobs

The default number of Vivado jobs is set inside the Tcl script. To override it from the command line, pass the job count as the first Tcl argument:

```bash
vivado -mode batch -source build_project.tcl -tclargs 16
```

In this example, Vivado uses 16 parallel jobs.

## Run Synthesis Only

To create the project and run synthesis without running implementation, pass `0` as the second Tcl argument:

```bash
vivado -mode batch -source build_project.tcl -tclargs 16 0
```

This is useful for checking that the RTL, IP, and constraints are loaded correctly before launching the full implementation flow.

## Generated Output

The script creates a local Vivado build directory:

```text
project_fb/vivado_build/
```

Generated Vivado project files, logs, reports, and implementation outputs are written under this directory. These files are build artifacts and do not need to be committed to Git.

## Suggested `.gitignore`

To keep the repository clean, the following generated files and directories should be ignored:

```gitignore
project_fb/vivado_build/
project_fb/.Xil/
project_fb/*.jou
project_fb/*.log
project_fb/*.str
project_fb/*.backup.jou
project_fb/*.backup.log
```

## Notes

- The repository does not include a Vivado `.xpr` file. The project is rebuilt from the Tcl script.
- The script automatically scans the local RTL, IP, and constraint directories.
- The design top is `bfly_acc_top_hbm`.
- If Vivado reports missing board files, install the VCU128 board definition and rerun the script.
