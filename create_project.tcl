# In the Vivado Tcl Console: set argv {sim}; source <path>/scripts/create_project.tcl
# Batch: vivado -mode batch -source scripts/create_project.tcl -tclargs sim ?output_directory?
# Use hardware instead of sim after entering the verified board values.
set script_path [file normalize [file dirname [info script]]]
set source_root [file dirname $script_path]
source [file join $script_path board_setup.tcl]

if {![info exists argv] || [llength $argv] == 0} {
    set project_mode sim
} else {
    set project_mode [lindex $argv 0]
}
if {$project_mode ni {sim hardware} || [llength $argv] > 2} {
    error "Usage: create_project.tcl sim|hardware ?output_directory?"
}
if {$project_mode eq "hardware"} {
    set project_board [baseball_board::read_config]
    set project_part [dict get $project_board part]
} else {
    set project_part xc7s50csga324-1
    if {[llength [get_parts -quiet $project_part]] != 1} {
        error "Install Spartan-7 device support for the simulation project, or run scripts/run_tests.ps1."
    }
}
if {[llength $argv] == 2} {
    set project_dir [file normalize [lindex $argv 1]]
} else {
    set project_dir [file join $source_root build $project_mode]
}
if {[file exists [file join $project_dir FPGA_BASEBALL_GAME.xpr]]} {
    error "Project already exists in $project_dir. Open it, or pass a new output_directory."
}
if {[current_project -quiet] ne ""} {
    error "Close the currently open Vivado project before creating another project."
}
create_project FPGA_BASEBALL_GAME $project_dir -part $project_part
set rtl_dir [file join $source_root rtl]
set sim_dir [file join $source_root sim]
add_files -fileset sources_1 -norecurse [glob -directory $rtl_dir *.v *.vh]
add_files -fileset sim_1 -norecurse [glob -directory $sim_dir tb_*.v]
set_property include_dirs [list $rtl_dir] [get_filesets sources_1]
set_property include_dirs [list $rtl_dir] [get_filesets sim_1]
set_property top baseball_top [get_filesets sources_1]
set_property top tb_baseball_top [get_filesets sim_1]
set_property top_auto_set 0 [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
if {$project_mode eq "hardware"} {
    baseball_board::install $project_board
}
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Created $project_mode project [file join $project_dir FPGA_BASEBALL_GAME.xpr]"
