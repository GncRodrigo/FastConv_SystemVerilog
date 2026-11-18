# Synthesize and route a streaming-column core at the shared 317 MHz point.
# Usage: synth_impl.tcl <repo-root> <output-root> <algorithm> <manifest> <constraints>
if {$argc != 5} { error "usage: synth_impl.tcl <repo-root> <output-root> <algorithm> <manifest> <constraints>" }
set repo_root [file normalize [lindex $argv 0]]
set output_root [file normalize [lindex $argv 1]]
set algorithm [lindex $argv 2]
set manifest [file normalize [lindex $argv 3]]
set constraints [file normalize [lindex $argv 4]]
set nbits 20
if {[info exists ::env(STREAM_COLUMN_NBITS)]} {
  set nbits $::env(STREAM_COLUMN_NBITS)
}
if {![string is integer -strict $nbits] || $nbits < 1} {
  error "STREAM_COLUMN_NBITS must be a positive integer, got '$nbits'"
}
# The campaigns use the ZCU104 part; STREAM_COLUMN_FPGA_PART targets another
# device (e.g. xck26-sfvc784-2LV-c for the Kria K26). The constraints only
# define the clock, so they do not depend on the board.
set part xczu7ev-ffvc1156-2-e
if {[info exists ::env(STREAM_COLUMN_FPGA_PART)] && $::env(STREAM_COLUMN_FPGA_PART) ne ""} {
  set part $::env(STREAM_COLUMN_FPGA_PART)
}
set run_dir [file join $output_root $algorithm]
file mkdir $run_dir

# "#@generic NAME=VALUE" lines in the manifest add or override top-level
# generics (e.g. N_CHANNEL_OUT=12 and NADDR=14 for the Cin3/Cout12 cores).
array set generic_value [list NADDR 12 NBITS $nbits]
set generic_order [list NADDR NBITS]
set sources [open $manifest r]
while {[gets $sources line] >= 0} {
  if {[regexp {^#@generic\s+([A-Za-z_][A-Za-z0-9_]*)=(\S+)} [string trim $line] -> gname gvalue]} {
    if {![info exists generic_value($gname)]} { lappend generic_order $gname }
    set generic_value($gname) $gvalue
  }
}
close $sources
set generics {}
foreach gname $generic_order { lappend generics "$gname=$generic_value($gname)" }

set fp [open [file join $run_dir metadata.txt] w]
puts $fp "vivado_version=[version -short]"
puts $fp "part=$part"
puts $fp "top=Conv"
puts $fp "algorithm=$algorithm"
puts $fp "target_period_ns=3.154574"
puts $fp "target_frequency_mhz=317"
puts $fp "generics=[join $generics { }]"
puts $fp "manifest=$manifest"
close $fp

set sources [open $manifest r]
while {[gets $sources line] >= 0} {
  set line [string trim $line]
  if {$line eq "" || [string match "#*" $line]} { continue }
  set source [file normalize [file join $repo_root $line]]
  if {![file exists $source]} { error "RTL source does not exist: $source" }
  read_verilog -sv $source
}
close $sources

read_xdc $constraints
synth_design -top Conv -part $part -generic $generics
write_checkpoint -force [file join $run_dir design_synth.dcp]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $run_dir design_routed.dcp]
write_verilog -force -mode funcsim [file join $run_dir design_routed_funcsim.v]
report_utilization -hierarchical -file [file join $run_dir utilization.rpt]
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose -max_paths 30 -file [file join $run_dir timing_summary.rpt]
report_clock_utilization -file [file join $run_dir clock_utilization.rpt]
report_io -file [file join $run_dir io.rpt]
report_drc -file [file join $run_dir drc.rpt]
puts "IMPLEMENTATION_COMPLETE algorithm=$algorithm"
exit
