//
// s2026_cpu_select.v
//   CPU select (Z80 / R800)
//   Revision 1.00
//
// Copyright (c) 2026 Takayuki Hara.
// All rights reserved.
//
// Redistribution and use of this source code or any derivative works, are
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Redistributions may not be sold, nor may they be used in a commercial
//    product or activity without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ----------------------------------------------------------------------------

module s2026_cpu_select (
	input			sys_reset_n,
	input			msx_reset_n,
	input			clk,
	input			cpu_pause,
	//	Z80 CPU run control (busrq/busakは使わず、コア側でM1境界に停止する方式)
	output			z80_run_req,
	input			z80_run_ack,
	//	R800 CPU run control
	output			r800_run_req,
	input			r800_run_ack,
	//	Pico run control (バスアイドル地点で停止する方式)
	output			pico_run_req,
	input			pico_run_ack,
	input			pico_change_req,
	input			pico_change_target,
	//	CPU change control (from s2026_register)
	input			cpu_change_req,
	input			cpu_change_target,
	//	Status
	output			z80_active,
	output			r800_active,
	output			processor_mode,
	output	[1:0]	cpu_sel
);
	//	cpu_sel: 00=Z80, 01=R800, 10=PICO(戻り先Z80), 11=PICO(戻り先R800)
	localparam	ST_IDLE		= 1'b0;
	localparam	ST_CHANGING	= 1'b1;

	reg				ff_state0 = ST_IDLE;
	reg				ff_state1 = ST_IDLE;
	reg		[1:0]	ff_cpu_sel = 2'b00;
	reg		[1:0]	ff_target_sel = 2'b00;
	wire			w_all_stopped;

	//	切替中はz80/r800/picoすべてのrun_reqを落とし、3者ともM1境界/バスアイドル地点で
	//	停止(run_ack=0)したことを確認してから切替先だけを再稼働させる。
	assign w_all_stopped = ( !z80_run_ack || !msx_reset_n ) && ( !r800_run_ack || !msx_reset_n ) && !pico_run_ack;

	// ---------------------------------------------------------
	//	CPU/Pico change state machine
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !msx_reset_n ) begin
			//	こちらはMSXリセットがかかるとリセットされる
			ff_state0			<= ST_IDLE;
			ff_cpu_sel[0]		<= 1'b0;
			ff_target_sel[0]	<= 1'b0;
		end
		else if( ff_state0 == ST_IDLE ) begin
			if( cpu_change_req ) begin
				ff_state0			<= ST_CHANGING;
				ff_target_sel[0]	<= ~cpu_change_target;
			end
		end
		else begin
			//	ST_CHANGING: z80/r800/picoすべてが停止(run_ack=0)するまで待ってから切り替える
			if( w_all_stopped ) begin
				ff_cpu_sel[0]	<= ff_target_sel[0];
				ff_state0		<= ST_IDLE;
			end
		end
	end

	always @( posedge clk ) begin
		if( !sys_reset_n ) begin
			//	こちらは全体のリセットの時にのみリセットされる
			ff_state1			<= ST_IDLE;
			ff_cpu_sel[1]		<= 1'b1;
			ff_target_sel[1]	<= 1'b1;
		end
		else if( ff_state1 == ST_IDLE ) begin
			if( pico_change_req ) begin
				ff_target_sel[1]	<= pico_change_target;
				ff_state1			<= ST_CHANGING;
			end
		end
		else begin
			//	ST_CHANGING: z80/r800/picoすべてが停止(run_ack=0)するまで待ってから切り替える
			if( w_all_stopped ) begin
				ff_cpu_sel[1]	<= ff_target_sel[1];
				ff_state1		<= ST_IDLE;
			end
		end
	end

	// ---------------------------------------------------------
	//	Output assignments
	// ---------------------------------------------------------
	assign z80_run_req		= cpu_pause ? 1'b0 : ( ( ff_state0 == ST_CHANGING || ff_state1 == ST_CHANGING ) ? 1'b0 : ( ff_cpu_sel == 2'b00 ) );
	assign r800_run_req		= cpu_pause ? 1'b0 : ( ( ff_state0 == ST_CHANGING || ff_state1 == ST_CHANGING ) ? 1'b0 : ( ff_cpu_sel == 2'b01 ) );
	assign pico_run_req		= cpu_pause ? 1'b0 : ( ( ff_state0 == ST_CHANGING || ff_state1 == ST_CHANGING ) ? 1'b0 : ff_cpu_sel[1] );

	assign z80_active		= ( ff_cpu_sel == 2'b00 );
	assign r800_active		= ( ff_cpu_sel == 2'b01 );
	assign processor_mode	= ~ff_cpu_sel[0];
	assign cpu_sel			= ff_cpu_sel;
endmodule
