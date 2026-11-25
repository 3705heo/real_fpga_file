# Shared procedures for the scripted project creator and the Vivado GUI.
namespace eval baseball_board {
    variable root [file normalize [file join [file dirname [info script]] ..]]
    variable masks {
        button_invert 31 led_invert 255 seg_com_invert 255 seg_data_invert 255
        seg_reverse 1 base_invert 7 rgb_r_invert 15 rgb_g_invert 15 rgb_b_invert 15
        piezo_invert 1 lcd_data_invert 255 lcd_ctrl_invert 7
    }
}

proc baseball_board::read_config {} {
    variable root
    variable masks
    source [file join $root constraints board_config.tcl]
    set missing {}
    foreach key [concat {part clk_hz io_default lcd_interface} [dict keys $masks]] {
        if {![dict exists $board $key] || [string trim [dict get $board $key]] eq ""} {
            lappend missing $key
        }
    }
    if {[llength $missing] != 0} {
        error "Hardware settings missing in constraints/board_config.tcl: [join $missing {, }]."
    }
    if {[dict get $board lcd_interface] ne "HD44780_8BIT_WRITE"} {
        error "lcd_interface must be verified as HD44780_8BIT_WRITE for the supplied driver."
    }
    set part [dict get $board part]
    if {![regexp {^xc7s[0-9]+[a-z0-9]+-[a-z0-9]+$} $part] || [llength [get_parts -quiet $part]] != 1} {
        error "Board part '$part' is not an installed Spartan-7 part."
    }
    set hz [dict get $board clk_hz]
    if {![regexp {^[1-9][0-9]*$} $hz] || $hz < 1000 || $hz > 2147483647} {
        error "clk_hz must be a decimal integer in 1000..2147483647."
    }
    foreach {key maximum} $masks {
        set value [dict get $board $key]
        if {![regexp {^(0|[1-9][0-9]*)$} $value] || $value > $maximum} {
            error "$key must be a decimal integer in 0..$maximum."
        }
    }
    set default [dict get $board io_default]
    if {$default eq "DEFAULT" || ![regexp {^[A-Z][A-Z0-9_]*$} $default]} {
        error "io_default must name a confirmed I/O standard."
    }
    if {![dict exists $board io_overrides]} {
        dict set board io_overrides {}
    }
    return $board
}

proc baseball_board::install {board} {
    variable root
    variable masks
    if {[current_project -quiet] eq ""} {
        error "Open a Vivado project before applying board settings."
    }
    set pins [file join $root constraints comm206_pins.xdc]
    set pin_file [open $pins r]
    set ports {}
    while {[gets $pin_file line] >= 0} {
        if {[regexp {^set_property PACKAGE_PIN \S+ \[get_ports \{?([^\s\}]+)\}?\]$} $line -> port]} {
            lappend ports $port
        }
    }
    close $pin_file
    if {[llength $ports] == 0} {
        error "No port names found in $pins."
    }
    set override [dict get $board io_overrides]
    dict for {name standard} $override {
        if {$standard eq "DEFAULT" || ![regexp {^[A-Z][A-Z0-9_]*$} $standard]} {
            error "Invalid I/O standard '$standard' for $name."
        }
        set matched 0
        foreach port $ports {
            set bus [lindex [split $port "\["] 0]
            if {$name eq $port || $name eq $bus} {
                set matched 1
            }
        }
        if {!$matched} {
            error "Unknown io_overrides port '$name'."
        }
    }
    set hz [dict get $board clk_hz]
    set generic [list CLK_HZ=$hz]
    foreach key [dict keys $masks] {
        lappend generic "[string toupper $key]=[dict get $board $key]"
    }
    set project [current_project]
    set settings [file join [get_property DIRECTORY $project] baseball_clock_io.generated.xdc]
    set out [open $settings w]
    puts $out "# Generated from constraints/board_config.tcl"
    puts $out [format {create_clock -name clk_sys -period %.9f [get_ports clk_sys]} [expr {1.0e9 / $hz}]]
    foreach port $ports {
        set bus [lindex [split $port "\["] 0]
        set standard [dict get $board io_default]
        if {[dict exists $override $bus]} {
            set standard [dict get $override $bus]
        }
        if {[dict exists $override $port]} {
            set standard [dict get $override $port]
        }
        puts $out [format {set_property IOSTANDARD %s [get_ports {%s}]} $standard $port]
    }
    close $out
    set_property part [dict get $board part] $project
    set_property generic $generic [get_filesets sources_1]
    foreach constraint [list $pins $settings] {
        if {[llength [get_files -quiet -of_objects [get_filesets constrs_1] $constraint]] == 0} {
            add_files -fileset constrs_1 -norecurse $constraint
        }
    }
    puts "Configured [dict get $board part] with CLK_HZ=$hz. Re-run implementation after any board change."
}

proc baseball_board::apply {} {
    install [read_config]
}
