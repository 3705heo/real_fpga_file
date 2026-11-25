# Batch: vivado -mode batch -source scripts/build_hardware.tcl -tclargs ?project.xpr?
set hardware_scripts [file normalize [file dirname [info script]]]
source [file join $hardware_scripts board_setup.tcl]
set hardware_board [baseball_board::read_config]
if {[llength $argv] > 1} {
    error "Usage: build_hardware.tcl ?project.xpr?"
}
set hardware_xpr [file join $hardware_scripts .. build hardware FPGA_BASEBALL_GAME.xpr]
if {[llength $argv] == 1} {
    set hardware_xpr [file normalize [lindex $argv 0]]
}
if {![file isfile $hardware_xpr]} {
    error "Hardware project missing at $hardware_xpr. Create it with create_project.tcl hardware."
}
open_project $hardware_xpr
baseball_board::install $hardware_board
reset_run synth_1
reset_run impl_1
launch_runs synth_1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {$synth_status ne "synth_design Complete!"} {
    error "Synthesis did not complete: $synth_status"
}
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
set status [get_property STATUS [get_runs impl_1]]
if {$status ne "write_bitstream Complete!"} {
    error "Bitstream generation did not complete: $status"
}
set bitstream [file join [get_property DIRECTORY [get_runs impl_1]] baseball_top.bit]
if {![file isfile $bitstream]} {
    error "Expected bitstream missing at $bitstream."
}
puts "Bitstream: $bitstream"
