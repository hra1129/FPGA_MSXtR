set ::compare_dir [file dirname [file normalize [info script]]]
set ::compare_log [open [file join $::compare_dir openmsx_compare.log] w]
set ::compare_stage boot
set ::compare_trace 0
set ::compare_trace_count 0
set ::compare_previous_pc -1
set save_settings_on_exit false
set ::compare_s1990 {}
foreach name [debug list] {
	if {[string match -nocase {*s1990*regs} $name]} {set ::compare_s1990 $name}
}
if {$::compare_s1990 eq {}} {error {S1990 register debuggable not found}}

proc compare_log {text} {
	puts $::compare_log $text
	flush $::compare_log
}

proc compare_state {label} {
	set text "$label stage=$::compare_stage"
	set status [debug read $::compare_s1990 6]
	append text [format " CPU=%s S1990_R6=%02X" [expr {$status & 0x20 ? "Z80" : "R800"}] $status]
	foreach name {PC SP AF BC DE HL IX IY} {
		if {![catch {reg $name} value]} {
			append text [format " %s=%04X" $name $value]
		}
	}
	set sp [reg SP]
	set saved_sp [expr {[debug read memory 0xFFFD] | ([debug read memory 0xFFFE] << 8)}]
	set return_address [expr {[debug read memory $sp] | ([debug read memory [expr {($sp + 1) & 0xFFFF}]] << 8)}]
	append text [format " saved_SP=%04X stack_word=%04X" $saved_sp $return_address]
	set hl [reg HL]
	set values {}
	for {set index 0} {$index < 12} {incr index} {
		lappend values [format %02X [debug read memory [expr {($hl + $index) & 0xFFFF}]]]
	}
	compare_log "$text HL_bytes=[join $values { }]"
}

proc compare_trace_step {} {
	set pc [reg PC]
	set ::compare_previous_pc $pc
	compare_state [format "TRACE %03d" $::compare_trace_count]
	incr ::compare_trace_count
	if {$::compare_trace_count >= 256} {set ::compare_trace 0}
}

compare_log "MACHINE [machine_info config_name]"
foreach address {0x0180 0x046A 0x04B9 0x04BB 0x04BF 0x04D1} {
	debug set_bp $address {} [list compare_state [format "BREAK %04X" $address]]
}
debug set_bp 0x0180 {$::compare_stage == "usr_first" || $::compare_stage == "usr_second"} {
	set ::compare_trace 1
	set ::compare_trace_count 0
	set ::compare_previous_pc -1
}
debug set_bp 0x04D1 {$::compare_stage == "usr_first" || $::compare_stage == "usr_second"} {
	set ::compare_trace 1
	set ::compare_trace_count 0
	set ::compare_previous_pc -1
}
debug set_condition {$::compare_trace && [reg PC] != $::compare_previous_pc} {compare_trace_step}

proc compare_begin {} {
	if {[catch {
		compare_state BOOT_DONE
		screenshot [file join $::compare_dir openmsx_boot.png]
		compare_log "BYTES_7910 [binary encode hex [debug read_block memory 0x7910 24]]"
		set ::compare_stage prepare_z80
		type_via_keybuf "POKE &HC000,&H3E:POKE &HC001,0:POKE &HC002,&HCD:POKE &HC003,&H80:POKE &HC004,1:POKE &HC005,&HC9:DEFUSR=&HC000:A=USR(0)\r"
		after time 3 compare_first
	} error]} {
		compare_log "ERROR begin: $error"
		exit
	}
}

proc compare_first {} {
	if {[catch {
		compare_state Z80_PREPARED
		if {([debug read $::compare_s1990 6] & 0x20) == 0} {error {Preparation did not select Z80}}
		screenshot [file join $::compare_dir openmsx_z80.png]
		compare_log "PREPARE_CODE [binary encode hex [debug read_block memory 0xC000 6]]"
		set ::compare_stage usr_first
		set ::compare_trace 0
		type_via_keybuf "DEFUSR=&H180:A=USR(0)\r"
		after time 3 compare_second
	} error]} {
		compare_log "ERROR prepare: $error"
		exit
	}
}

proc compare_second {} {
	if {[catch {
		compare_state FIRST_DONE
		if {[debug read $::compare_s1990 6] & 0x20} {error {First USR did not select R800}}
		screenshot [file join $::compare_dir openmsx_first.png]
		set ::compare_stage usr_second
		set ::compare_trace 0
		type_via_keybuf "A=USR(0)\r"
		after time 3 compare_finish
	} error]} {
		compare_log "ERROR second: $error"
		exit
	}
}

proc compare_finish {} {
	compare_state SECOND_DONE
	screenshot [file join $::compare_dir openmsx_second.png]
	compare_log COMPLETE
	close $::compare_log
	exit
}

set throttle off
after time 20 compare_begin