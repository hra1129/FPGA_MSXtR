`timescale 1ns/1ps

module tb;
	localparam real CLK_PERIOD_PS = 1_000_000_000_000.0 / 42_954_540.0;

	reg			reset_n;
	reg			clk;
	reg			enable_z80;
	reg			enable_r800;

	reg			z80_m1_n;
	reg			z80_mreq_n;
	reg			z80_iorq_n;
	reg			z80_rd_n;
	reg			z80_wr_n;
	reg	[15:0]	z80_a;
	reg	[7:0]	z80_wdata;
	wire	[7:0]	z80_rdata;

	reg			r800_m1_n;
	reg			r800_mreq_n;
	reg			r800_iorq_n;
	reg			r800_rd_n;
	reg			r800_wr_n;
	reg	[15:0]	r800_a;
	reg	[7:0]	r800_wdata;
	wire	[7:0]	r800_rdata;

	wire			wait_n;
	wire			bus_m1;
	wire			bus_io;
	wire			bus_write;
	wire			bus_valid;
	wire	[7:0]	bus_wdata;
	wire	[15:0]	bus_address;

	wire			bus_uart_cs;
	reg	[7:0]	bus_uart_rdata;
	reg			bus_uart_rdata_en;
	reg			bus_uart_ready;

	wire			bus_bootrom_cs;
	reg	[7:0]	bus_bootrom_rdata;
	reg			bus_bootrom_rdata_en;
	reg			bus_bootrom_ready;

	wire			z80_active;
	wire			r800_active;
	wire			processor_mode;

	integer		trans_count;
	reg			prev_bus_valid;
	reg			mon_bus_m1;
	reg			mon_bus_io;
	reg			mon_bus_write;
	reg			mon_uart_cs;
	reg			mon_bootrom_cs;
	reg	[15:0]	mon_address;
	reg	[7:0]	mon_wdata;

	reg	[3:0]	div12;
	reg			div2;
	integer		before_count;
	reg	[7:0]	read_data;
	reg			wait_read_done;

	s2026 u_dut (
		.reset_n				( reset_n				),
		.clk					( clk					),
		.enable_z80				( enable_z80			),
		.enable_r800			( enable_r800			),
		.wait_n					( wait_n				),
		.z80_m1_n				( z80_m1_n				),
		.z80_mreq_n				( z80_mreq_n			),
		.z80_iorq_n				( z80_iorq_n			),
		.z80_rd_n				( z80_rd_n				),
		.z80_wr_n				( z80_wr_n				),
		.z80_a					( z80_a					),
		.z80_wdata				( z80_wdata				),
		.z80_rdata				( z80_rdata				),
		.r800_m1_n				( r800_m1_n				),
		.r800_mreq_n			( r800_mreq_n			),
		.r800_iorq_n			( r800_iorq_n			),
		.r800_rd_n				( r800_rd_n				),
		.r800_wr_n				( r800_wr_n				),
		.r800_a					( r800_a				),
		.r800_wdata				( r800_wdata			),
		.r800_rdata				( r800_rdata			),
		.bus_m1					( bus_m1				),
		.bus_io					( bus_io				),
		.bus_write				( bus_write				),
		.bus_valid				( bus_valid				),
		.bus_wdata				( bus_wdata				),
		.bus_address			( bus_address			),
		.bus_uart_cs			( bus_uart_cs			),
		.bus_uart_rdata			( bus_uart_rdata		),
		.bus_uart_rdata_en		( bus_uart_rdata_en		),
		.bus_uart_ready			( bus_uart_ready		),
		.bus_bootrom_cs			( bus_bootrom_cs		),
		.bus_bootrom_rdata		( bus_bootrom_rdata		),
		.bus_bootrom_rdata_en	( bus_bootrom_rdata_en	),
		.bus_bootrom_ready		( bus_bootrom_ready		),
		.z80_active				( z80_active			),
		.r800_active			( r800_active			),
		.processor_mode			( processor_mode		)
	);

	always #(CLK_PERIOD_PS / 2.0) begin
		clk <= ~clk;
	end

	always @(posedge clk) begin
		if (!reset_n) begin
			div12 <= 4'd0;
			div2 <= 1'b0;
			enable_z80 <= 1'b0;
			enable_r800 <= 1'b0;
		end
		else begin
			enable_z80 <= (div12 == 4'd0);
			if (div12 == 4'd11) begin
				div12 <= 4'd0;
			end
			else begin
				div12 <= div12 + 4'd1;
			end

			enable_r800 <= (div2 == 1'b0);
			div2 <= ~div2;
		end
	end

	function automatic [7:0] bootrom_func;
		input [15:0] addr;
		begin
			bootrom_func = addr[7:0] ^ 8'h5A;
		end
	endfunction

	always @(*) begin
		bus_uart_rdata = 8'h00;
		bus_uart_rdata_en = 1'b0;
		if (bus_uart_cs && bus_valid && !bus_write) begin
			bus_uart_rdata = 8'hA5;
			bus_uart_rdata_en = 1'b1;
		end
	end

	always @(*) begin
		bus_bootrom_rdata = 8'h00;
		bus_bootrom_rdata_en = 1'b0;
		if (bus_bootrom_cs && bus_valid && !bus_write) begin
			bus_bootrom_rdata = bootrom_func(bus_address);
			bus_bootrom_rdata_en = 1'b1;
		end
	end

	always @(posedge clk) begin
		if (!reset_n) begin
			prev_bus_valid <= 1'b0;
			trans_count <= 0;
			mon_bus_m1 <= 1'b0;
			mon_bus_io <= 1'b0;
			mon_bus_write <= 1'b0;
			mon_uart_cs <= 1'b0;
			mon_bootrom_cs <= 1'b0;
			mon_address <= 16'h0000;
			mon_wdata <= 8'h00;
		end
		else begin
			prev_bus_valid <= bus_valid;
			if (!prev_bus_valid && bus_valid) begin
				trans_count <= trans_count + 1;
				mon_bus_m1 <= bus_m1;
				mon_bus_io <= bus_io;
				mon_bus_write <= bus_write;
				mon_uart_cs <= bus_uart_cs;
				mon_bootrom_cs <= bus_bootrom_cs;
				mon_address <= bus_address;
				mon_wdata <= bus_wdata;
			end
		end
	end

	task automatic wait_z80_tick;
		begin
			@(posedge clk);
			while (!enable_z80) begin
				@(posedge clk);
			end
		end
	endtask

	task automatic wait_new_transaction;
		input integer prev_count;
		integer timeout;
		begin
			timeout = 0;
			while (trans_count == prev_count && timeout < 3000) begin
				@(posedge clk);
				timeout = timeout + 1;
			end
			if (trans_count == prev_count) begin
				$display("ERROR: transaction timeout");
				$fatal(1);
			end
		end
	endtask

	task automatic wait_bus_valid_low;
		integer timeout;
		begin
			timeout = 0;
			while (bus_valid && timeout < 3000) begin
				@(posedge clk);
				timeout = timeout + 1;
			end
			if (bus_valid) begin
				$display("ERROR: bus_valid did not deassert");
				$fatal(1);
			end
		end
	endtask

	task automatic wait_z80_wait_release;
		begin
			while (!wait_n) begin
				wait_z80_tick();
			end
		end
	endtask

	task automatic z80_io_write;
		input [15:0] addr;
		input [7:0] data;
		begin
			wait_z80_tick();
			z80_a <= addr;
			z80_wdata <= data;
			z80_m1_n <= 1'b1;
			z80_mreq_n <= 1'b1;
			z80_iorq_n <= 1'b0;
			z80_rd_n <= 1'b1;
			z80_wr_n <= 1'b0;

			wait_z80_tick();
			wait_z80_wait_release();
			z80_iorq_n <= 1'b1;
			z80_wr_n <= 1'b1;
			z80_wdata <= 8'h00;
		end
	endtask

	task automatic z80_io_read;
		input [15:0] addr;
		output [7:0] data;
		begin
			wait_z80_tick();
			z80_a <= addr;
			z80_m1_n <= 1'b1;
			z80_mreq_n <= 1'b1;
			z80_iorq_n <= 1'b0;
			z80_rd_n <= 1'b0;
			z80_wr_n <= 1'b1;

			wait_z80_tick();
			wait_z80_wait_release();
			data = z80_rdata;
			z80_iorq_n <= 1'b1;
			z80_rd_n <= 1'b1;
		end
	endtask

	task automatic z80_mem_read;
		input [15:0] addr;
		output [7:0] data;
		begin
			wait_z80_tick();
			z80_a <= addr;
			z80_m1_n <= 1'b1;
			z80_mreq_n <= 1'b0;
			z80_iorq_n <= 1'b1;
			z80_rd_n <= 1'b0;
			z80_wr_n <= 1'b1;

			wait_z80_tick();
			wait_z80_wait_release();
			data = z80_rdata;
			z80_mreq_n <= 1'b1;
			z80_rd_n <= 1'b1;
		end
	endtask

	task automatic z80_mem_write;
		input [15:0] addr;
		input [7:0] data;
		begin
			wait_z80_tick();
			z80_a <= addr;
			z80_wdata <= data;
			z80_m1_n <= 1'b1;
			z80_mreq_n <= 1'b0;
			z80_iorq_n <= 1'b1;
			z80_rd_n <= 1'b1;
			z80_wr_n <= 1'b0;

			wait_z80_tick();
			wait_z80_wait_release();
			z80_mreq_n <= 1'b1;
			z80_wr_n <= 1'b1;
			z80_wdata <= 8'h00;
		end
	endtask

	initial begin
		clk = 1'b0;
		reset_n = 1'b0;
		enable_z80 = 1'b0;
		enable_r800 = 1'b0;
		div12 = 4'd0;
		div2 = 1'b0;
		trans_count = 0;
		prev_bus_valid = 1'b0;

		z80_m1_n = 1'b1;
		z80_mreq_n = 1'b1;
		z80_iorq_n = 1'b1;
		z80_rd_n = 1'b1;
		z80_wr_n = 1'b1;
		z80_a = 16'h0000;
		z80_wdata = 8'h00;

		r800_m1_n = 1'b1;
		r800_mreq_n = 1'b1;
		r800_iorq_n = 1'b1;
		r800_rd_n = 1'b1;
		r800_wr_n = 1'b1;
		r800_a = 16'h0000;
		r800_wdata = 8'h00;

		bus_uart_ready = 1'b1;
		bus_bootrom_ready = 1'b1;

		repeat (20) @(posedge clk);
		reset_n = 1'b1;
		repeat (2) wait_z80_tick();

		before_count = trans_count;
		z80_io_write(16'h00E4, 8'h06);
		wait_new_transaction(before_count);
		if (!(mon_bus_io && mon_bus_write && !mon_bus_m1 && mon_address == 16'h00E4 && mon_wdata == 8'h06 && !mon_uart_cs && !mon_bootrom_cs)) begin
			$display("ERROR: IO write E4 bus conversion mismatch");
			$fatal(1);
		end

		before_count = trans_count;
		z80_io_read(16'h00E4, read_data);
		wait_new_transaction(before_count);
		if (!(mon_bus_io && !mon_bus_write && !mon_bus_m1 && mon_address == 16'h00E4 && !mon_uart_cs && !mon_bootrom_cs)) begin
			$display("ERROR: IO read E4 bus conversion mismatch");
			$fatal(1);
		end
		if (read_data !== 8'h06) begin
			$display("ERROR: IO read E4 data mismatch expected=06 got=%02h", read_data);
			$fatal(1);
		end

		before_count = trans_count;
		z80_io_read(16'h0010, read_data);
		wait_new_transaction(before_count);
		if (!(mon_bus_io && !mon_bus_write && !mon_bus_m1 && mon_address == 16'h0010 && mon_uart_cs && !mon_bootrom_cs)) begin
			$display("ERROR: UART read bus conversion mismatch");
			$fatal(1);
		end
		if (read_data !== 8'hA5) begin
			$display("ERROR: UART read data mismatch expected=A5 got=%02h", read_data);
			$fatal(1);
		end

		before_count = trans_count;
		z80_io_write(16'h0011, 8'hC3);
		wait_new_transaction(before_count);
		if (!(mon_bus_io && mon_bus_write && !mon_bus_m1 && mon_address == 16'h0011 && mon_wdata == 8'hC3 && mon_uart_cs && !mon_bootrom_cs)) begin
			$display("ERROR: UART write bus conversion mismatch");
			$fatal(1);
		end

		before_count = trans_count;
		z80_mem_read(16'h1234, read_data);
		wait_new_transaction(before_count);
		if (!(!mon_bus_io && !mon_bus_write && !mon_bus_m1 && mon_address == 16'h1234 && !mon_uart_cs && mon_bootrom_cs)) begin
			$display("ERROR: MEM read bus conversion mismatch");
			$fatal(1);
		end
		if (read_data !== bootrom_func(16'h1234)) begin
			$display("ERROR: MEM read data mismatch expected=%02h got=%02h", bootrom_func(16'h1234), read_data);
			$fatal(1);
		end

		before_count = trans_count;
		z80_mem_write(16'h1235, 8'h5C);
		wait_new_transaction(before_count);
		if (!(!mon_bus_io && mon_bus_write && !mon_bus_m1 && mon_address == 16'h1235 && mon_wdata == 8'h5C && !mon_uart_cs && mon_bootrom_cs)) begin
			$display("ERROR: MEM write bus conversion mismatch");
			$fatal(1);
		end

		bus_uart_ready = 1'b0;
		before_count = trans_count;
		wait_read_done = 1'b0;
		fork
			begin
				z80_io_read(16'h0010, read_data);
				wait_read_done = 1'b1;
			end
		join_none
		wait_new_transaction(before_count);
		if (!(mon_bus_io && !mon_bus_write && !mon_bus_m1 && mon_address == 16'h0010 && mon_uart_cs && !mon_bootrom_cs)) begin
			$display("ERROR: UART wait-state bus conversion mismatch");
			$fatal(1);
		end
		if (!bus_valid) begin
			$display("ERROR: bus_valid dropped while bus_ready is low");
			$fatal(1);
		end
		if (wait_n) begin
			$display("ERROR: wait_n is not asserted low during wait-state");
			$fatal(1);
		end
		if (z80_iorq_n || z80_rd_n || !z80_wr_n) begin
			$display("ERROR: Z80 read control signals are not stretched during wait-state");
			$fatal(1);
		end
		repeat (16) @(posedge clk);
		if (!bus_valid) begin
			$display("ERROR: bus_valid did not stay asserted during wait-state");
			$fatal(1);
		end
		if (wait_n) begin
			$display("ERROR: wait_n was released before bus_ready");
			$fatal(1);
		end
		if (z80_iorq_n || z80_rd_n || !z80_wr_n) begin
			$display("ERROR: Z80 read control signals did not keep stretched state");
			$fatal(1);
		end
		if (trans_count != (before_count + 1)) begin
			$display("ERROR: unexpected transaction count change during wait-state");
			$fatal(1);
		end
		bus_uart_ready = 1'b1;
		wait_bus_valid_low();
		while (!wait_read_done) begin
			@(posedge clk);
		end
		if (!(z80_iorq_n && z80_rd_n && z80_wr_n)) begin
			$display("ERROR: Z80 read control signals did not release after wait-state");
			$fatal(1);
		end
		if (read_data !== 8'hA5) begin
			$display("ERROR: UART wait-state read data mismatch expected=A5 got=%02h", read_data);
			$fatal(1);
		end

		$display("PASS: s2026 Z80->bus conversion test completed");
		$finish;
	end
endmodule
