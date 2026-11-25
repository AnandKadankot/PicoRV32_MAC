# vivado_bitstream.tcl - full-system implementation of fpga_top to a bitstream.
# Usage: vivado -mode batch -source vivado_bitstream.tcl -tclargs <outdir> <core_mhz> [explore]
#   explore: use timing-driven directives for place/route/phys_opt
set outdir   [file normalize [lindex $argv 0]]
set core_mhz [lindex $argv 1]
set explore  [expr {[lindex $argv 2] eq "explore"}]
set root     [file normalize [file dirname [info script]]/..]
set part     xc7z020clg400-1
file mkdir $outdir
set_param general.maxThreads 8

read_verilog [list $root/third_party/picorv32/picorv32.v $root/rtl/pcpi_mac.v \
                   $root/rtl/core_top.v $root/rtl/fpga_top.v]
read_xdc $root/constraints/pynq_z2.xdc
synth_design -top fpga_top -part $part \
	-generic CORE_MHZ=$core_mhz -generic FIRMWARE=\"$root/sw/build/bench_rv32imc_mac.hex\"
if {$explore} {
	opt_design -directive Explore
	place_design -directive ExtraTimingOpt
	phys_opt_design -directive AggressiveExplore
	route_design -directive AggressiveExplore
	phys_opt_design -directive AggressiveExplore
} else {
	opt_design
	place_design
	phys_opt_design
	route_design
}

report_utilization                 -file $outdir/util.rpt
report_utilization -hierarchical   -file $outdir/util_hier.rpt
report_timing_summary -max_paths 10 -file $outdir/timing.rpt
report_clock_utilization           -file $outdir/clocks.rpt
report_power                       -file $outdir/power.rpt
report_drc                         -file $outdir/drc.rpt
report_methodology                 -file $outdir/methodology.rpt
report_clock_networks              -file $outdir/clock_networks.rpt
report_design_analysis -congestion -file $outdir/congestion.rpt
report_design_analysis -complexity -file $outdir/complexity.rpt
report_design_analysis -timing -max_paths 10 -file $outdir/path_analysis.rpt
report_route_status                -file $outdir/route_status.rpt
write_checkpoint -force $outdir/fpga_top_routed.dcp
write_bitstream -force $outdir/fpga_top.bit

set crit [get_timing_paths -max_paths 1 -setup]
set fh [open $outdir/summary.txt w]
puts $fh "core_mhz $core_mhz"
puts $fh "explore $explore"
puts $fh "wns [get_property SLACK $crit]"
puts $fh "whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]"
puts $fh "crit_start [get_property STARTPOINT_PIN $crit]"
puts $fh "crit_end [get_property ENDPOINT_PIN $crit]"
puts $fh "crit_levels [get_property LOGIC_LEVELS $crit]"
puts $fh "crit_skew [get_property SKEW $crit]"
puts $fh "crit_datapath [get_property DATAPATH_DELAY $crit]"
set worst_skew 0.0
foreach p [get_timing_paths -max_paths 1000 -nworst 1 -setup] {
	set sk [get_property SKEW $p]
	if {$sk ne "" && abs($sk) > abs($worst_skew)} { set worst_skew $sk }
}
puts $fh "worst_setup_path_skew $worst_skew"
puts $fh "bitstream [file exists $outdir/fpga_top.bit]"
close $fh
