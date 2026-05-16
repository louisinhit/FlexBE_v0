# build_project.tcl
# Recreate and build the FlexBE VCU128/HBM Vivado project from repository sources.
# Place this file in: FlexBE_v0/project_fb/
# Usage:
#   vivado -mode batch -source build_project.tcl
#   vivado -mode batch -source build_project.tcl -tclargs 16
#   vivado -mode batch -source build_project.tcl -tclargs 16 0   ;# create + synth only

set PROJECT_NAME "project_fb_rebuild"
set TOP          "bfly_acc_top_hbm"
set PART         "xcvu37p-fsvh2892-2L-e"
set BOARD_PART   "xilinx.com:vcu128:part0:1.0"
set JOBS         16
set RUN_IMPL     1

if {$argc >= 1} {
    set JOBS [lindex $argv 0]
}
if {$argc >= 2} {
    set RUN_IMPL [lindex $argv 1]
}

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set SRC_DIR    [file join $SCRIPT_DIR sources_1 imports design]
set IP_DIR     [file join $SCRIPT_DIR sources_1 ip]
set XDC_DIR    [file join $SCRIPT_DIR constrs_1 new]
set BUILD_DIR  [file join $SCRIPT_DIR vivado_build]
set REPORT_DIR [file join $BUILD_DIR reports]

proc find_files {dir patterns} {
    set result {}
    if {![file isdirectory $dir]} {
        return $result
    }

    foreach pattern $patterns {
        foreach f [glob -nocomplain -types f -directory $dir $pattern] {
            lappend result [file normalize $f]
        }
    }

    foreach subdir [glob -nocomplain -types d -directory $dir *] {
        set result [concat $result [find_files $subdir $patterns]]
    }

    return [lsort -unique $result]
}

proc require_files {files what} {
    if {[llength $files] == 0} {
        error "No $what files found. Check repository path and directory layout."
    }
}

file mkdir $BUILD_DIR
file mkdir $REPORT_DIR
catch {close_project -quiet}

puts "INFO: Script directory: $SCRIPT_DIR"
puts "INFO: Build directory : $BUILD_DIR"
puts "INFO: Target part     : $PART"
puts "INFO: Top module      : $TOP"

create_project -force $PROJECT_NAME $BUILD_DIR -part $PART

catch {set_property board_part $BOARD_PART [current_project]} board_msg
if {$board_msg ne ""} {
    puts "WARNING: Could not set board_part to $BOARD_PART. Vivado message: $board_msg"
}

catch {set_property target_language Verilog [current_project]}
catch {set_property default_lib xil_defaultlib [current_project]}

# -----------------------------------------------------------------------------
# Add RTL sources
# -----------------------------------------------------------------------------
set rtl_files [find_files $SRC_DIR {*.v *.sv *.vh}]
require_files $rtl_files "RTL"
puts "INFO: Adding [llength $rtl_files] RTL files."
add_files -fileset sources_1 -norecurse $rtl_files
set_property include_dirs [list $SRC_DIR] [get_filesets sources_1]

# -----------------------------------------------------------------------------
# Add existing Vivado IP customizations (.xci)
# -----------------------------------------------------------------------------
set ip_files [find_files $IP_DIR {*.xci}]
require_files $ip_files "IP/XCI"
puts "INFO: Reading [llength $ip_files] IP files."
foreach xci $ip_files {
    read_ip $xci
}

set ips [get_ips -quiet *]
if {[llength $ips] > 0} {
    report_ip_status -file [file join $REPORT_DIR ip_status_initial.rpt]
    generate_target all $ips
    catch {export_ip_user_files -of_objects $ips -no_script -sync -force -quiet}
}

# -----------------------------------------------------------------------------
# Add constraints
# -----------------------------------------------------------------------------
set xdc_files [find_files $XDC_DIR {*.xdc}]
require_files $xdc_files "XDC"
puts "INFO: Adding [llength $xdc_files] XDC files."
add_files -fileset constrs_1 -norecurse $xdc_files
foreach xdc $xdc_files {
    set_property used_in {synthesis implementation} [get_files $xdc]
}

# -----------------------------------------------------------------------------
# Top and compile order
# -----------------------------------------------------------------------------
set_property top $TOP [get_filesets sources_1]
set_property top_lib xil_defaultlib [get_filesets sources_1]
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------------
# Run strategies copied from project_fb_fp.xpr
#   synth_1: Flow_PerfOptimized_high
#   impl_1 : Performance_ExploreWithRemap
# -----------------------------------------------------------------------------
set synth_run [get_runs synth_1]
set impl_run  [get_runs impl_1]

set_property strategy Flow_PerfOptimized_high $synth_run
set_property strategy Performance_ExploreWithRemap $impl_run
set_property AUTO_INCREMENTAL_CHECKPOINT false $synth_run
set_property AUTO_INCREMENTAL_CHECKPOINT false $impl_run
set_property WRITE_INCREMENTAL_SYNTH_CHECKPOINT false $synth_run
set_property WRITE_INCREMENTAL_SYNTH_CHECKPOINT false $impl_run

# Extra implementation option seen in the reference .xpr.
# Different Vivado versions expose the property name slightly differently, hence catch.
catch {set_property STEPS.ROUTE_DESIGN.ARGS.MORE_OPTIONS {-tns_cleanup} $impl_run}
catch {set_property "STEPS.ROUTE_DESIGN.ARGS.MORE OPTIONS" {-tns_cleanup} $impl_run}
catch {set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $impl_run}

# Save the recreated project before launching runs.
save_project

# -----------------------------------------------------------------------------
# Build
# -----------------------------------------------------------------------------
puts "INFO: Launching synthesis with $JOBS jobs."
launch_runs synth_1 -jobs $JOBS
wait_on_run synth_1
open_run synth_1 -name synth_1
report_utilization -file [file join $REPORT_DIR synth_utilization.rpt]
report_timing_summary -file [file join $REPORT_DIR synth_timing_summary.rpt]

if {$RUN_IMPL} {
    puts "INFO: Launching implementation to bitstream with $JOBS jobs."
    launch_runs impl_1 -to_step write_bitstream -jobs $JOBS
    wait_on_run impl_1
    open_run impl_1 -name impl_1
    report_timing_summary -file [file join $REPORT_DIR impl_timing_summary.rpt]
    report_utilization -file [file join $REPORT_DIR impl_utilization.rpt]
    report_route_status -file [file join $REPORT_DIR impl_route_status.rpt]
    report_power -file [file join $REPORT_DIR impl_power.rpt]
}

puts "INFO: Done. Project: [file join $BUILD_DIR ${PROJECT_NAME}.xpr]"
puts "INFO: Reports: $REPORT_DIR"
