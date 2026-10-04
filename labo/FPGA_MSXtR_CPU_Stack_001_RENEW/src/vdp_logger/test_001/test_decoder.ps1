$ErrorActionPreference = 'Stop'
$root = '/mnt/c/Users/hra/Documents/github/HRA_product/FPGA_MSXtR'
$firmware = "$root/controller/FPGA_MSXtR_Stack_Controller_001"
$test = "$root/labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/vdp_logger/test_001/decoder_test.c"
wsl --exec gcc -std=c11 -Wall -Wextra -Werror "-I$firmware" "$firmware/vdp_logger.c" $test -o /tmp/msxtr_vdp_logger_test
if ($LASTEXITCODE -ne 0) { throw 'Decoder compilation failed' }
$actual = ((wsl --exec /tmp/msxtr_vdp_logger_test) -join "`n").Trim()
if ($LASTEXITCODE -ne 0) { throw 'Decoder execution failed' }
$expected = @'
[1] out 0x98, 0x55
[1] R#14 = 0x00
[1] R#00 = 0x00
[1] R#01 = 0x60
[1] R#15 = 0x00
[2] S#00 = 0x9F
[3] vpoke 0x1800, 0x41
[4] vpeek( 0x0012 ) = 0x20
[4] vpeek( 0x0013 ) = 0x21
[1] R#16 = 0x03
[5] P#03 = (7,2,0)
[1] R#17 = 0x20
[6] R#32 = 0xAA
[6] R#33 = 0xBB
[1] R#17 = 0xA0
[6] R#32 = 0xAB
[6] R#32 = 0xAC
[1] R#14 = 0x04
[7] vpeek( 0x10012 ) = 0x30
[1] R#00 = 0x04
[1] R#14 = 0x00
[8] vpeek( 0x3FFF ) = 0x10
[8] vpeek( 0x4000 ) = 0x11
[4294967295] out 0x9C, 0x80
[0] in( 0x9C ) = 0x81
[9] in( 0x9A ) = 0xFF
'@
$expected = (($expected.Trim().Replace("`r", '') -split "`n") | ForEach-Object { "$_ ; PC=0x531C" }) -join "`n"
if ($actual -cne $expected) {
	Write-Output $actual
	throw 'VDP decoder output mismatch'
}
Write-Output 'PASS: register, status, palette, indirect, VRAM read buffer, bank wrap, raw ports, timestamp, unmatched second'