if {![info exists test_root]} {set test_root /tb}
onerror {quit -code 1 -f}
onbreak {if {[examine -radix unsigned ${test_root}/test_passed] == 1} {quit -code 0 -f} else {quit -code 1 -f}}
onfinish stop
log -r /*
add wave -r /*
run -all
if {[examine -radix unsigned ${test_root}/test_passed] == 1} {
	quit -code 0 -f
} else {
	quit -code 1 -f
}