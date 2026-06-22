# ================================================================================== #
# MAC-Accelerator - populate the Vivado project with sources, libraries, top, XDC.    #
# Run once (re-runnable): vivado -mode batch -source scripts/add_sources.tcl          #
# Adapted from the prior HFT run_synth.tcl flow (open_project + add_files).            #
# ================================================================================== #

set proj_dir    "D:/vivado projects/MAC-Accelerator"
set neorv32_rtl "D:/vivado projects/neorv32/rtl/core"

open_project "$proj_dir/MAC-Accelerator.xpr"

# ---- NEORV32 core: all rtl/core/*.vhd EXCEPT the upstream CFU (we override it) ----- #
set core_files [glob -nocomplain "$neorv32_rtl/*.vhd"]
set upstream_cfu "$neorv32_rtl/neorv32_cpu_alu_cfu.vhd"
set core_files [lsearch -all -inline -not $core_files $upstream_cfu]
add_files -norecurse -fileset sources_1 $core_files
set_property library neorv32 [get_files $core_files]

# ---- Project override CFU (MAC) + MAC datapath, also into library 'neorv32' -------- #
set my_neorv32 [list \
  "$proj_dir/rtl/neorv32_cpu_alu_cfu.vhd" \
  "$proj_dir/rtl/mac_datapath.vhd" ]
add_files -norecurse -fileset sources_1 $my_neorv32
set_property library neorv32 [get_files $my_neorv32]

# ---- Top-level (default library) -------------------------------------------------- #
add_files -norecurse -fileset sources_1 "$proj_dir/rtl/neorv32_zedboard_top.vhd"

# ---- Simulation testbenches ------------------------------------------------------- #
add_files -norecurse -fileset sim_1 [list \
  "$proj_dir/sim/mac_datapath_tb.vhd" \
  "$proj_dir/sim/mac_cfu_tb.vhd" ]

# ---- Constraints ------------------------------------------------------------------ #
add_files -norecurse -fileset constrs_1 "$proj_dir/constraints/zedboard_mac.xdc"

# ---- Top entity + VHDL-2008 everywhere -------------------------------------------- #
set_property top neorv32_zedboard_top [get_filesets sources_1]
set_property file_type {VHDL 2008} [get_files -of [get_filesets sources_1] *.vhd]
set_property file_type {VHDL 2008} [get_files -of [get_filesets sim_1] *.vhd]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "INFO: sources added. Top = neorv32_zedboard_top. Part = [get_property PART [current_project]]"
close_project
