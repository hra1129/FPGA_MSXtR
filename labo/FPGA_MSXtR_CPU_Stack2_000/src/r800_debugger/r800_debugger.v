module r800_debugger (
	input reset_n,
	input clk,
	input [1:0] cpu_sel,
	input [15:0] pc,
	input [15:0] sp,
	input [15:0] af,
	input [15:0] hl,
	input m1_n,
	input [15:0] fetch_address,
	input bus_io,
	input bus_valid,
	input bus_write,
	input bus_ready,
	input [15:0] bus_address,
	input [7:0] bus_wdata,
	input bus_rdata_en,
	input [7:0] bus_rdata,
	input arm,
	output [7:0] count,
	output done,
	input read_request,
	input [6:0] read_address,
	output read_valid,
	output [127:0] read_record
);
	reg [127:0] memory [0:127];
	reg [7:0] ff_count;
	reg ff_started;
	reg ff_finished;
	reg ff_ret_seen;
	reg [15:0] ff_snapshot_pc;
	reg [1:0] ff_previous_owner;
	reg ff_read_seen;
	reg ff_read_pending;
	reg ff_pending_io;
	reg [15:0] ff_pending_address;
	reg [1:0] ff_pending_owner;
	reg [15:0] ff_pending_pc;
	reg [47:0] ff_pending_registers;
	reg ff_write_seen;
	reg [15:0] ff_write_address0;
	reg [15:0] ff_write_address1;
	reg [7:0] ff_write_data0;
	reg [7:0] ff_write_data1;
	reg [1:0] ff_write_valid;
	reg [31:0] ff_ticks;
	reg ff_read_valid;
	reg [127:0] ff_read_record;
	wire w_active = !cpu_sel[1];
	wire w_write = w_active && bus_valid && bus_write && bus_ready && !ff_write_seen;
	wire w_memory_write = w_write && !bus_io;
	wire w_read_accept = w_active && bus_valid && !bus_write && bus_ready && !ff_read_seen;
	wire w_read = bus_rdata_en && (w_read_accept || ff_read_pending);
	wire w_start = !ff_started && w_active && !m1_n && fetch_address == 16'h0180;
	wire w_return = ff_ret_seen && w_active && pc != 16'h04d1 && pc != 16'h04d2;
	wire w_snapshot = w_active && !m1_n && fetch_address != ff_snapshot_pc && (fetch_address == 16'h04bb || fetch_address == 16'h04bf || fetch_address == 16'h04d1);
	wire w_owner = ff_started && w_active && cpu_sel != ff_previous_owner;
	wire [15:0] w_stack_high = sp + 16'd1;
	wire w_stack_low_known = (ff_write_valid[0] && ff_write_address0 == sp) || (ff_write_valid[1] && ff_write_address1 == sp);
	wire w_stack_high_known = (ff_write_valid[0] && ff_write_address0 == w_stack_high) || (ff_write_valid[1] && ff_write_address1 == w_stack_high);
	wire [7:0] w_stack_low = ff_write_address0 == sp ? ff_write_data0 : ff_write_data1;
	wire [7:0] w_stack_high_data = ff_write_address0 == w_stack_high ? ff_write_data0 : ff_write_data1;
	wire [3:0] w_event = w_start ? 4'd1 : w_write ? 4'd4 : w_read ? 4'd3 : w_return ? 4'd6 : w_owner ? 4'd5 : w_snapshot ? 4'd2 : 4'd0;
	wire w_delayed_read = w_event == 4'd3 && !w_read_accept;
	wire [15:0] w_address = w_start ? {w_stack_high_data, w_stack_low} : w_delayed_read ? ff_pending_address : bus_address;
	wire [15:0] w_record_pc = w_start || w_event == 4'd2 ? fetch_address : w_delayed_read ? ff_pending_pc : pc;
	wire [47:0] w_registers = w_delayed_read ? ff_pending_registers : {sp, af, hl};
	wire [1:0] w_record_owner = w_delayed_read ? ff_pending_owner : cpu_sel;
	wire w_record_io = w_delayed_read ? ff_pending_io : bus_io;
	wire [7:0] w_data = w_start ? {6'd0, w_stack_high_known, w_stack_low_known} : w_write ? bus_wdata : w_read ? bus_rdata : 8'd0;
	wire w_record = !done && (w_start || (ff_started && w_event != 4'd0));
	assign count = ff_count;
	assign done = ff_finished || ff_count == 8'd128;
	assign read_valid = ff_read_valid;
	assign read_record = ff_read_record;
	always @(posedge clk) begin
		if( !reset_n || arm ) begin
			ff_count <= 0;
			ff_started <= 0;
			ff_finished <= 0;
			ff_ret_seen <= 0;
			ff_snapshot_pc <= 16'hffff;
			ff_previous_owner <= 2'b10;
			ff_read_seen <= 0;
			ff_read_pending <= 0;
			ff_pending_io <= 0;
			ff_pending_address <= 0;
			ff_pending_owner <= 0;
			ff_pending_pc <= 0;
			ff_pending_registers <= 0;
			ff_write_seen <= 0;
			ff_write_address0 <= 0;
			ff_write_address1 <= 0;
			ff_write_data0 <= 0;
			ff_write_data1 <= 0;
			ff_write_valid <= 0;
			ff_ticks <= 0;
			ff_read_valid <= 0;
			ff_read_record <= 0;
		end
		else begin
			ff_ticks <= ff_ticks + 32'd1;
			if( !bus_valid || bus_write || cpu_sel[1] ) ff_read_seen <= 0;
			else if( w_read_accept ) ff_read_seen <= 1;
			if( w_read_accept ) begin
				ff_pending_address <= bus_address;
				ff_pending_owner <= cpu_sel;
				ff_pending_pc <= pc;
				ff_pending_registers <= {sp, af, hl};
				ff_pending_io <= bus_io;
				ff_read_pending <= !bus_rdata_en;
			end
			else if( bus_rdata_en ) ff_read_pending <= 0;
			if( !bus_valid || !bus_write || cpu_sel[1] ) ff_write_seen <= 0;
			else if( w_write ) ff_write_seen <= 1;
			if( w_memory_write ) begin
				ff_write_address1 <= ff_write_address0;
				ff_write_data1 <= ff_write_data0;
				ff_write_address0 <= bus_address;
				ff_write_data0 <= bus_wdata;
				ff_write_valid <= {ff_write_valid[0], 1'b1};
			end
			if( ff_started && w_active && pc == 16'h04d1 ) ff_ret_seen <= 1;
			if( w_record ) begin
				memory[ff_count[6:0]] <= {ff_ticks, w_registers[15:0], w_registers[31:16], w_registers[47:32], w_record_pc, w_address, w_data, w_record_owner[0], 2'd0, w_record_io, w_event};
				ff_count <= ff_count + 8'd1;
				ff_started <= 1;
				if( w_event == 4'd6 ) ff_finished <= 1;
				if( w_event == 4'd1 || w_event == 4'd5 ) ff_previous_owner <= cpu_sel;
				if( w_event == 4'd2 ) ff_snapshot_pc <= fetch_address;
			end
			ff_read_valid <= read_request && {1'b0, read_address} < ff_count;
			if( read_request && {1'b0, read_address} < ff_count ) ff_read_record <= memory[read_address];
		end
	end
endmodule