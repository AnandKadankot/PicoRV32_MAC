# vivado_impl.tcl - out-of-context synthesis + place & route of core_top.
# Usage: vivado -mode batch -source vivado_impl.tcl -tclargs <outdir> <period_ns> [GENERIC=VALUE ...]
#
# Out-of-context mode keeps the memory bus off device pins, so the timing that
# is reported is the core's own register-to-register paths.

set outdir [lindex $argv 0]
set period [lindex $argv 1]
set generics [lrange $argv 2 end]
set part   xc7z020clg400-1
set root   [file normalize [file dirname [info script]]/..]

file mkdir $outdir
set_param general.maxThreads 2

read_verilog [list \
	$root/third_party/picorv32/picorv32.v \
	$root/rtl/pcpi_mac.v \
	$root/rtl/core_top.v]

set gen_args {}
foreach g $generics { lappend gen_args -generic $g }

synth_design -top core_top -part $part -mode out_of_context {*}$gen_args
create_clock -name clk -period $period [get_ports clk]

opt_design
place_design
phys_opt_design
route_design

report_utilization                -file $outdir/util.rpt
report_utilization -hierarchical  -file $outdir/util_hier.rpt
report_timing_summary -max_paths 5 -file $outdir/timing.rpt
report_power                      -file $outdir/power.rpt

# machine-readable summary
set wns  [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set crit [get_timing_paths -max_paths 1 -setup]
set fh [open $outdir/summary.txt w]
puts $fh "period $period"
puts $fh "wns $wns"
puts $fh "lut [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT}]]"
puts $fh "ff [llength [get_cells -hier -filter {PRIMITIVE_GROUP == FLOP_LATCH}]]"
puts $fh "dsp [llength [get_cells -hier -filter {REF_NAME =~ DSP48*}]]"
puts $fh "carry [llength [get_cells -hier -filter {REF_NAME == CARRY4}]]"
puts $fh "crit_start [get_property STARTPOINT_PIN $crit]"
puts $fh "crit_end [get_property ENDPOINT_PIN $crit]"
puts $fh "crit_levels [get_property LOGIC_LEVELS $crit]"
close $fh
