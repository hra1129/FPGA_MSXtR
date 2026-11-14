set ::script_dir [file dirname [file normalize [info script]]]
set ::output_dir $::env(TEMP)
set ::commands [list \
	{10 OUT &HD8,&HA1:OUT &HD9,&H16} \
	{20 FOR I=0 TO 31:POKE &HC000+I,INP(&HD9):NEXT I} \
	{30 FOR J=0 TO 7} \
	{40 A=PEEK(&HC000+J):C=PEEK(&HC008+J):GOSUB 1000} \
	{50 NEXT J} \
	{60 FOR J=0 TO 7} \
	{70 A=PEEK(&HC010+J):C=PEEK(&HC018+J):GOSUB 1000} \
	{80 NEXT J} \
	{90 POKE &HC100,&H5A} \
	{100 END} \
	{1000 FOR B=7 TO 0 STEP -1} \
	{1010 IF A AND 2^B THEN PRINT CHR$(49); ELSE PRINT CHR$(48);} \
	{1020 NEXT B} \
	{1030 PRINT " ";} \
	{1040 FOR B=7 TO 0 STEP -1} \
	{1050 IF C AND 2^B THEN PRINT CHR$(49); ELSE PRINT CHR$(48);} \
	{1060 NEXT B} \
	{1070 PRINT} \
	{1080 RETURN}]
set ::command_index 0
set ::log_file [open [file join $::output_dir openmsx_kanji_basic.log] w]
set save_settings_on_exit false
set throttle off

proc send_basic_line {} {
	if {$::command_index >= [llength $::commands]} {
		type_via_keybuf "RUN\r"
		after time 5 finish_test
		return
	}
	type_via_keybuf "[lindex $::commands $::command_index]\r"
	incr ::command_index
	after time 1 send_basic_line
}

proc finish_test {} {
	set bytes [debug read_block memory 0xC000 32]
	set marker [debug read memory 0xC100]
	puts $::log_file "MACHINE [machine_info config_name]"
	puts $::log_file "KANJI_JIS1 3441 D8=A1 D9=16 PHYSICAL 00B420; OpenMSX four-block byte layout"
	puts $::log_file [format "BASIC_RUN_MARKER %02X" $marker]
	puts $::log_file "BYTES [binary encode hex $bytes]"
	if {$marker != 0x5A} {puts $::log_file "ERROR BASIC program did not reach its completion marker"}
	flush $::log_file
	screenshot [file join $::output_dir openmsx_kanji_basic.png]
	close $::log_file
	exit
}

proc begin_test {} {
	puts $::log_file "BASIC Kanji read test started on [machine_info config_name]"
	type_via_keybuf "OUT &HD8,&HA1:OUT &HD9,&H16\r"
	after time 2 send_basic_line
}

puts "Starting OpenMSX BASIC Kanji read test"
after time 20 begin_test