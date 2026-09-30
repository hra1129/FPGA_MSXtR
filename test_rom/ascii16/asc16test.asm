; =============================================================================
; ASCII16 test ROM
; 16KB x 8banks
;   Revision 1.00
;
; Copyright (c) 2026 Takayuki Hara.
; All rights reserved.
;
; Redistribution and use of this source code or any derivative works, are
; permitted provided that the following conditions are met:
;
; 1. Redistributions of source code must retain the above copyright notice,
;    this list of conditions and the following disclaimer.
; 2. Redistributions in binary form must reproduce the above copyright
;    notice, this list of conditions and the following disclaimer in the
;    documentation and/or other materials provided with the distribution.
; 3. Redistributions may not be sold, nor may they be used in a commercial
;    product or activity without specific prior written permission.
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
; TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
; PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
; CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
; EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
; PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
; OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
; ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;
; ----------------------------------------------------------------------------

outdo		:=			0x0018
chgmod		:=			0x005F
bank_reg	:=			0x6000

bank_image	macro		BANK_NAME, BANK_ID
			org			0x4000

			db			"AB"
			dw			start
			dw			0
			dw			0
			dw			0
			dw			0
			dw			0
			dw			0
start:
			ld			a, 1
			call		chgmod
put_message:
			ld			hl, s_message
loop:
			ld			a, [hl]
			or			a, a
			jr			z, exit_loop
			rst			0x18
			inc			hl
			jr			loop
exit_loop:
			ld			a, (BANK_ID + 1) & 7
			ld			[bank_reg], a
			jp			put_message
s_message:
			db			BANK_NAME, 10, 13, 0
			align		16384
			endm

			scope		bank0
			bank_image	"BANK0", 0
			endscope

			scope		bank1
			bank_image	"BANK1", 1
			endscope

			scope		bank2
			bank_image	"BANK2", 2
			endscope

			scope		bank3
			bank_image	"BANK3", 3
			endscope

			scope		bank4
			bank_image	"BANK4", 4
			endscope

			scope		bank5
			bank_image	"BANK5", 5
			endscope

			scope		bank6
			bank_image	"BANK6", 6
			endscope

			scope		bank7
			bank_image	"BANK7", 7
			endscope
