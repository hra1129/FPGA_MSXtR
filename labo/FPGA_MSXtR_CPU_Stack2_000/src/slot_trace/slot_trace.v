//
// slot_trace.v
//   Slot register write tracer (A8h / FFFFh / CPU owner / MSX reset)
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
//	Entry format (64bit)
//		[63:40]	timestamp (about 1us unit, 24bit wrap)
//		[39:24]	PC of the bus master (Z80 or R800)
//		[23:16]	new value
//		[15:8]	old value
//		[7:4]	event type
//				1: A8h write, 2: FFFFh write (SLOT#0), 3: FFFFh write (SLOT#3)
//				4: CPU owner change (old/new = cpu_sel)
//				5: MSX reset asserted, 6: MSX reset released
//				7: memory mapper write (old = I/O port number)
//		[3:2]	cpu_sel (00: Z80, 01: R800, 1x: Pico)
//		[1:0]	reserved
//
//	Control
//		bit0: clear buffer and trigger state
//		bit1: trigger enable (A8h write with trigger_value)
//		bit2: memory mapper write logging enable
//		bit3: hold (stop recording)
//
//	read_signal (128bit)
//		[63:0]		entry at read_index (0: oldest)
//		[79:64]		number of entries
//		[95:80]		trigger entry index (valid when triggered)
//		[103:96]	flags (bit0: trigger enable, bit1: mapper enable, bit2: hold,
//					       bit3: triggered, bit4: frozen)
//		[111:104]	trigger value
//		[127:112]	reserved
// ----------------------------------------------------------------------------

module slot_trace (
	input			reset_n,
	input			clk,
	input			msx_reset_n,
	input	[1:0]	cpu_sel,
	input	[15:0]	pc,
	input			ppi_write,
	input			secondary_write,
	input			mapper_write,
	input	[7:0]	io_address,
	input	[7:0]	wdata,
	input	[7:0]	primary_slot,
	input	[7:0]	secondary_slot0,
	input	[7:0]	secondary_slot3,
	input			control_write,
	input	[7:0]	control,
	input	[7:0]	trigger_value,
	input	[9:0]	read_index,
	output	[127:0]	read_signal
);
	localparam	[3:0]	EV_PRIMARY		= 4'd1;
	localparam	[3:0]	EV_SECONDARY0	= 4'd2;
	localparam	[3:0]	EV_SECONDARY3	= 4'd3;
	localparam	[3:0]	EV_CPU_SEL		= 4'd4;
	localparam	[3:0]	EV_RESET_ON		= 4'd5;
	localparam	[3:0]	EV_RESET_OFF	= 4'd6;
	localparam	[3:0]	EV_MAPPER		= 4'd7;
	localparam	[6:0]	POST_TRIGGER	= 7'd64;

	reg		[63:0]	memory [0:1023];
	reg		[63:0]	ff_read_data;
	reg		[9:0]	ff_read_address;

	reg		[5:0]	ff_us_prescaler;
	reg		[23:0]	ff_timestamp;
	reg				ff_ppi_write_d;
	reg				ff_secondary_write_d;
	reg				ff_mapper_write_d;
	reg		[1:0]	ff_cpu_sel_d;
	reg				ff_msx_reset_n_d;
	reg				ff_cpu_pending;
	reg		[1:0]	ff_cpu_old;
	reg		[1:0]	ff_cpu_new;
	reg				ff_reset_on_pending;
	reg				ff_reset_off_pending;

	reg				ff_trigger_en;
	reg				ff_mapper_en;
	reg				ff_hold;
	reg		[7:0]	ff_trigger_value;
	reg				ff_triggered;
	reg				ff_frozen;
	reg		[6:0]	ff_post_count;
	reg		[9:0]	ff_trigger_address;
	reg		[9:0]	ff_write_pointer;
	reg		[10:0]	ff_count;

	wire			w_bus_primary;
	wire			w_bus_secondary;
	wire			w_bus_mapper;
	wire			w_bus_event;
	reg		[3:0]	w_type;
	reg		[7:0]	w_old;
	reg		[7:0]	w_new;
	wire			w_event;
	wire			w_record;
	wire			w_trigger;
	wire	[63:0]	w_entry;
	wire	[9:0]	w_oldest;
	wire	[9:0]	w_trigger_index;

	assign w_bus_primary	= ppi_write & ~ff_ppi_write_d;
	assign w_bus_secondary	= secondary_write & ~ff_secondary_write_d;
	assign w_bus_mapper		= mapper_write & ~ff_mapper_write_d & ff_mapper_en;
	assign w_bus_event		= w_bus_primary | w_bus_secondary | w_bus_mapper;

	always @(*) begin
		if( w_bus_primary ) begin
			w_type	= EV_PRIMARY;
			w_old	= primary_slot;
			w_new	= wdata;
		end
		else if( w_bus_secondary ) begin
			w_type	= (primary_slot[7:6] == 2'd0) ? EV_SECONDARY0 : EV_SECONDARY3;
			w_old	= (primary_slot[7:6] == 2'd0) ? secondary_slot0 : secondary_slot3;
			w_new	= wdata;
		end
		else if( w_bus_mapper ) begin
			w_type	= EV_MAPPER;
			w_old	= io_address;
			w_new	= wdata;
		end
		else if( ff_cpu_pending ) begin
			w_type	= EV_CPU_SEL;
			w_old	= { 6'd0, ff_cpu_old };
			w_new	= { 6'd0, ff_cpu_new };
		end
		else if( ff_reset_on_pending ) begin
			w_type	= EV_RESET_ON;
			w_old	= 8'd0;
			w_new	= 8'd0;
		end
		else begin
			w_type	= EV_RESET_OFF;
			w_old	= 8'd0;
			w_new	= 8'd0;
		end
	end

	assign w_event			= w_bus_event | ff_cpu_pending | ff_reset_on_pending | ff_reset_off_pending;
	assign w_record			= w_event & ~ff_frozen & ~ff_hold & ~control_write;
	assign w_trigger		= w_record & w_bus_primary & ff_trigger_en & ~ff_triggered & (wdata == ff_trigger_value);
	assign w_entry			= { ff_timestamp, pc, w_new, w_old, w_type, cpu_sel, 2'd0 };
	assign w_oldest			= ff_count[10] ? ff_write_pointer : 10'd0;
	assign w_trigger_index	= ff_trigger_address - w_oldest;

	// --------------------------------------------------------------------
	//	Timestamp (42.95454MHz / 43 = about 1us)
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_us_prescaler	<= 6'd0;
			ff_timestamp	<= 24'd0;
		end
		else if( ff_us_prescaler == 6'd42 ) begin
			ff_us_prescaler	<= 6'd0;
			ff_timestamp	<= ff_timestamp + 24'd1;
		end
		else begin
			ff_us_prescaler	<= ff_us_prescaler + 6'd1;
		end
	end

	// --------------------------------------------------------------------
	//	Event detection
	//	Bus writes have priority. CPU owner and reset changes wait as
	//	pending events until a cycle without a bus write.
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_ppi_write_d			<= 1'b0;
			ff_secondary_write_d	<= 1'b0;
			ff_mapper_write_d		<= 1'b0;
			ff_cpu_sel_d			<= cpu_sel;
			ff_msx_reset_n_d		<= msx_reset_n;
			ff_cpu_pending			<= 1'b0;
			ff_cpu_old				<= 2'b00;
			ff_cpu_new				<= 2'b00;
			ff_reset_on_pending		<= 1'b0;
			ff_reset_off_pending	<= 1'b0;
		end
		else begin
			ff_ppi_write_d			<= ppi_write;
			ff_secondary_write_d	<= secondary_write;
			ff_mapper_write_d		<= mapper_write;
			ff_cpu_sel_d			<= cpu_sel;
			ff_msx_reset_n_d		<= msx_reset_n;

			if( ff_cpu_sel_d != cpu_sel ) begin
				ff_cpu_pending		<= 1'b1;
				ff_cpu_old			<= ff_cpu_sel_d;
				ff_cpu_new			<= cpu_sel;
			end
			else if( !w_bus_event ) begin
				ff_cpu_pending		<= 1'b0;
			end

			if( ff_msx_reset_n_d && !msx_reset_n ) begin
				ff_reset_on_pending	<= 1'b1;
			end
			else if( !w_bus_event && !ff_cpu_pending ) begin
				ff_reset_on_pending	<= 1'b0;
			end

			if( !ff_msx_reset_n_d && msx_reset_n ) begin
				ff_reset_off_pending	<= 1'b1;
			end
			else if( !w_bus_event && !ff_cpu_pending && !ff_reset_on_pending ) begin
				ff_reset_off_pending	<= 1'b0;
			end
		end
	end

	// --------------------------------------------------------------------
	//	Recorder
	//	After the trigger, POST_TRIGGER more entries are recorded and then
	//	the buffer is frozen until the next clear.
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_trigger_en		<= 1'b1;
			ff_mapper_en		<= 1'b0;
			ff_hold				<= 1'b0;
			ff_trigger_value	<= 8'h22;
			ff_triggered		<= 1'b0;
			ff_frozen			<= 1'b0;
			ff_post_count		<= 7'd0;
			ff_trigger_address	<= 10'd0;
			ff_write_pointer	<= 10'd0;
			ff_count			<= 11'd0;
		end
		else if( control_write ) begin
			ff_trigger_en		<= control[1];
			ff_mapper_en		<= control[2];
			ff_hold				<= control[3];
			ff_trigger_value	<= trigger_value;
			if( control[0] ) begin
				ff_triggered		<= 1'b0;
				ff_frozen			<= 1'b0;
				ff_post_count		<= 7'd0;
				ff_trigger_address	<= 10'd0;
				ff_write_pointer	<= 10'd0;
				ff_count			<= 11'd0;
			end
		end
		else if( w_record ) begin
			ff_write_pointer	<= ff_write_pointer + 10'd1;
			if( !ff_count[10] ) begin
				ff_count		<= ff_count + 11'd1;
			end
			if( w_trigger ) begin
				ff_triggered		<= 1'b1;
				ff_trigger_address	<= ff_write_pointer;
				ff_post_count		<= POST_TRIGGER;
			end
			else if( ff_triggered ) begin
				ff_post_count	<= ff_post_count - 7'd1;
				if( ff_post_count == 7'd1 ) begin
					ff_frozen	<= 1'b1;
				end
			end
		end
	end

	always @( posedge clk ) begin
		if( w_record ) begin
			memory[ ff_write_pointer ] <= w_entry;
		end
		ff_read_address	<= w_oldest + read_index;
		ff_read_data	<= memory[ ff_read_address ];
	end

	assign read_signal = {
			16'd0,
			ff_trigger_value,
			3'd0, ff_frozen, ff_triggered, ff_hold, ff_mapper_en, ff_trigger_en,
			6'd0, w_trigger_index,
			5'd0, ff_count,
			ff_read_data
		};
endmodule
