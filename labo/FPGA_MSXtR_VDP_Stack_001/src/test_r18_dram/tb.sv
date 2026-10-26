`timescale 1ps/1ps

module tb;
	localparam integer c_ticks_per_line = 1368;
	localparam integer c_clocks_per_tick = 4;
	localparam integer c_core_clocks_per_line = c_ticks_per_line * c_clocks_per_tick;
	reg clk = 1'b0;
	reg reset_n = 1'b0;
	reg [2:0] bus_address = 3'd0;
	reg bus_ioreq = 1'b0;
	reg bus_write = 1'b0;
	reg bus_valid = 1'b0;
	reg [7:0] bus_wdata = 8'd0;
	wire bus_ready;
	wire [7:0] bus_rdata;
	wire bus_rdata_en;
	wire int_n;
	wire [17:2] vram_address;
	wire vram_write;
	wire vram_valid;
	wire [31:0] vram_wdata;
	wire [3:0] vram_wdata_mask;
	reg [31:0] vram_rdata = 32'd0;
	reg vram_rdata_en = 1'b0;
	wire vram_refresh;
	wire display_hs;
	wire display_vs;
	wire display_en;
	wire [7:0] display_r;
	wire [7:0] display_g;
	wire [7:0] display_b;
	wire [7:0] pulse;
	integer csv_file;
	integer adjust_value;
	integer raw_value;
	integer case_index;
	integer core_cycle;
	integer clock_index;
	integer request_count = 0;
	integer refresh_count = 0;
	reg [18:0] physical_address;
	reg [7:0] source_code;

	always #5821 clk = ~clk;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			vram_rdata_en <= 1'b0;
		end
		else begin
			vram_rdata_en <= vram_valid && !vram_write;
		end
	end

	vdp u_vdp (
		.reset_n(reset_n), .clk(clk), .initial_busy(1'b0),
		.bus_address(bus_address), .bus_ioreq(bus_ioreq), .bus_write(bus_write),
		.bus_valid(bus_valid), .bus_ready(bus_ready), .bus_wdata(bus_wdata),
		.bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en), .int_n(int_n),
		.vram_address(vram_address), .vram_write(vram_write), .vram_valid(vram_valid),
		.vram_wdata(vram_wdata), .vram_wdata_mask(vram_wdata_mask),
		.vram_rdata(vram_rdata), .vram_rdata_en(vram_rdata_en), .vram_refresh(vram_refresh),
		.display_hs(display_hs), .display_vs(display_vs), .display_en(display_en),
		.display_r(display_r), .display_g(display_g), .display_b(display_b),
		.force_highspeed(1'b0), .button(2'b11),
		.pulse0(pulse[0]), .pulse1(pulse[1]), .pulse2(pulse[2]), .pulse3(pulse[3]),
		.pulse4(pulse[4]), .pulse5(pulse[5]), .pulse6(pulse[6]), .pulse7(pulse[7])
	);

	task automatic write_register(input [5:0] register_number, input [7:0] value);
		begin
			@( negedge clk );
			bus_address = 3'd1;
			bus_ioreq = 1'b1;
			bus_write = 1'b1;
			bus_valid = 1'b0;
			wait( bus_ready );
			@( negedge clk );
			bus_wdata = value;
			bus_valid = 1'b1;
			@( negedge clk );
			bus_valid = 1'b0;
			wait( bus_ready );
			@( negedge clk );
			bus_wdata = {2'b10, register_number};
			bus_valid = 1'b1;
			@( negedge clk );
			bus_valid = 1'b0;
			wait( bus_ready );
			repeat(4) @( posedge clk );
			@( negedge clk );
			bus_ioreq = 1'b0;
			bus_write = 1'b0;
			repeat(4) @( posedge clk );
		end
	endtask

	task automatic wait_scanline_start;
		begin
			wait( u_vdp.u_timing_control.u_ssg.ff_v_active );
			wait( u_vdp.u_timing_control.u_ssg.ff_half_count != 0 );
			wait( u_vdp.u_timing_control.u_ssg.ff_half_count == 0 );
			@( negedge clk );
			#1;
		end
	endtask

	task automatic capture_line(input integer current_adjust, input integer current_raw);
		begin
			for( core_cycle = 0; core_cycle < c_core_clocks_per_line; core_cycle = core_cycle + 1 ) begin
				@( negedge clk );
				#1;
				clock_index = core_cycle / c_clocks_per_tick;
				if( vram_valid ) begin
					case( u_vdp.u_vram_interface.ff_vram_rdata_sel )
					3'd1: source_code = 8'd1;
					3'd2: source_code = 8'd2;
					3'd3: source_code = 8'd3;
					3'd4: source_code = 8'd4;
					default: source_code = 8'd0;
					endcase
					physical_address = {vram_address, 2'b00};
					$fstrobe(csv_file, "DRAM,%0d,%0d,%0d,%0d,%0d,%05h,%0h,%0d,%0d,%0d,%0d,%0d,%03h,%0d,%03h,%0d,%03h",
						current_adjust, current_raw, clock_index, core_cycle, source_code,
						vram_write, physical_address, vram_wdata_mask, vram_refresh,
						u_vdp.w_screen_mode_vram_valid, u_vdp.w_sprite_vram_valid,
						u_vdp.w_command_vram_valid, u_vdp.u_vram_interface.ff_vram_rdata_sel,
						u_vdp.u_timing_control.u_ssg.ff_half_count[11:2],
						u_vdp.u_upscan.w_even_we, u_vdp.u_upscan.w_even_address,
						u_vdp.u_upscan.w_odd_we, u_vdp.u_upscan.w_odd_address);
					request_count = request_count + 1;
				end
				if( vram_refresh ) begin
					$fstrobe(csv_file, "REFRESH,%0d,%0d,%0d,%0d,0,00000,0,1,0,0,0,0,%03h,0,%03h,0,%03h",
						current_adjust, current_raw, clock_index, core_cycle,
						u_vdp.u_timing_control.u_ssg.ff_half_count[11:2],
						u_vdp.u_upscan.w_even_address, u_vdp.u_upscan.w_odd_address);
					refresh_count = refresh_count + 1;
				end
				if( u_vdp.u_upscan.w_even_we || u_vdp.u_upscan.w_odd_we ) begin
					$fstrobe(csv_file, "UPSCAN,%0d,%0d,%0d,%0d,0,00000,0,0,0,0,0,0,%03h,%0d,%03h,%0d,%03h",
						current_adjust, current_raw, clock_index, core_cycle,
						u_vdp.u_timing_control.u_ssg.ff_half_count[11:2],
						u_vdp.u_upscan.w_even_we, u_vdp.u_upscan.w_even_address,
						u_vdp.u_upscan.w_odd_we, u_vdp.u_upscan.w_odd_address);
				end
			end
		end

	endtask

	task automatic initialize_case(input integer current_raw);
			begin
				reset_n = 1'b0;
				bus_ioreq = 1'b0;
				bus_write = 1'b0;
				bus_valid = 1'b0;
				repeat(20) @( posedge clk );
				@( negedge clk );
				reset_n = 1'b1;
				write_register(6'd0, 8'h00);
				write_register(6'd1, 8'h50);
				write_register(6'd2, 8'h06);
				write_register(6'd3, 8'h80);
				write_register(6'd4, 8'h00);
				write_register(6'd5, 8'h36);
				write_register(6'd6, 8'h07);
				write_register(6'd7, 8'h07);
				write_register(6'd8, 8'h0A);
				write_register(6'd9, 8'h00);
				write_register(6'd10, 8'h00);
				write_register(6'd11, 8'h00);
				write_register(6'd25, 8'h00);
				write_register(6'd26, 8'h00);
				write_register(6'd27, 8'h00);
				write_register(6'd18, {4'd0, current_raw[3:0]});
				wait_scanline_start();
			end
		endtask

	initial begin
		$display("One physical line = 5472 clk85m = 1368 clk21m; R18 sweep -7 through +8");
		csv_file = $fopen("r18_dram_events.csv", "w");
		$fdisplay(csv_file, "kind,adjust,raw,clock21,core_cycle,source,write,address_byte,mask,refresh,bg_req,sprite_req,command_req,owner,half_x,even_we,even_addr,odd_we,odd_addr");
		for( adjust_value = -7; adjust_value <= 8; adjust_value = adjust_value + 1 ) begin
			raw_value = (8 - adjust_value) & 15;
			initialize_case(raw_value);
			$display("CAPTURE adjust=%0d R18H=%h v_count=%0d", adjust_value, raw_value, u_vdp.u_timing_control.u_ssg.ff_v_count);
			capture_line(adjust_value, raw_value);
		end
		$fclose(csv_file);
		$display("PASS: captured %0d R#18 values", 16);
		$display("PASS: captured %0d VDP DRAM requests and %0d refresh pulses", request_count, refresh_count);
		$finish;
	end

	initial begin
		#(64'd2_000_000_000_000);
		$fatal(1, "R#18 DRAM trace timeout");
	end
endmodule