# ================================================================================== #
# MAC-Accelerator - run the self-checking testbenches in Vivado xsim (batch).         #
# vivado -mode batch -source scripts/run_sim.tcl -tclargs <tb_name>                   #
#   <tb_name> = mac_datapath_tb (default) | mac_cfu_tb                                 #
# Run scripts/add_sources.tcl first.                                                   #
# ================================================================================== #

set proj_dir "D:/vivado projects/MAC-Accelerator"
set tb "mac_datapath_tb"
if {$argc >= 1} { set tb [lindex $argv 0] }

open_project "$proj_dir/MAC-Accelerator.xpr"
set_property top $tb [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
run all
close_project
