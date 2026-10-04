onerror {quit -code 1 -f}
onbreak {if {[examine -radix unsigned /tb/test_passed] == 1} {quit -code 0 -f} else {quit -code 1 -f}}
onfinish stop
run -all
quit -code 1 -f