# ================================================================================== #
# MAC-Accelerator - synthesize, implement, write bitstream, dump timing + resources.  #
# vivado -mode batch -source scripts/build_bitstream.tcl                               #
# Run scripts/add_sources.tcl first. Adapted from the HFT build_bitstream.tcl flow.    #
# ================================================================================== #

set proj_dir "D:/vivado projects/MAC-Accelerator"
open_project "$proj_dir/MAC-Accelerator.xpr"

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 6
wait_on_run impl_1

# ---- Reports (Phase 6 gate: timing closure + DSP/LUT/FF resource report) ----------- #
open_run impl_1
puts "==================== TIMING SUMMARY ===================="
report_timing_summary -max_paths 5 -file "$proj_dir/reports/timing_summary.rpt"
set wns [get_property STATS.WNS [get_runs impl_1]]
puts "Worst Negative Slack (WNS) = $wns ns"
if {$wns >= 0} { puts "TIMING: CLOSED" } else { puts "TIMING: FAILED -> consider multi-cycle MAC fallback" }

puts "==================== UTILIZATION ======================="
report_utilization -file "$proj_dir/reports/utilization.rpt"
report_utilization -cells [get_cells -hier -filter {PRIMITIVE_GROUP == DSP}] -quiet

close_project
