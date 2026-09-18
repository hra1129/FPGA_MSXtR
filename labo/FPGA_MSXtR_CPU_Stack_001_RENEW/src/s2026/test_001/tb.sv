`timescale 1ns/1ps

module tb;
	localparam real c_clk_period = 1000.0 / 42.95454;

	reg				clk;
	reg				reset_n;
	reg				cpu_pause;

	wire			z80_run_req;
	reg				z80_run_ack;
	wire			r800_run_req;
	reg				r800_run_ack;
	wire			pico_run_req;
	reg				pico_run_ack;
	reg				pico_change_req;
	reg				pico_change_target;

	reg				bus_cs;
	reg				bus_write;
	reg				bus_valid;
	wire			bus_ready;
	reg		[7:0]	bus_wdata;
	reg		[1:0]	bus_address;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;

	wire			z80_active;
	wire			r800_active;
	wire			processor_mode;
	wire	[1:0]	cpu_sel;

	integer			pass_count;
	integer			fail_count;

	//	CPUモデル: run_req が下がってから run_ack を下げるまでの遅延サイクル数
	integer			z80_ack_delay;
	integer			r800_ack_delay;
	integer			pico_ack_delay;
	integer			z80_ack_counter;
	integer			r800_ack_counter;
	integer			pico_ack_counter;

	s2026 u_dut (
		.sys_reset_n		( reset_n				),
		.msx_reset_n		( reset_n				),
		.clk				( clk					),
		.cpu_pause			( cpu_pause				),
		.z80_run_req		( z80_run_req			),
		.z80_run_ack		( z80_run_ack			),
		.r800_run_req		( r800_run_req			),
		.r800_run_ack		( r800_run_ack			),
		.pico_run_req		( pico_run_req			),
		.pico_run_ack		( pico_run_ack			),
		.pico_change_req	( pico_change_req		),
		.pico_change_target	( pico_change_target	),
		.bus_cs				( bus_cs				),
		.bus_write			( bus_write				),
		.bus_valid			( bus_valid				),
		.bus_ready			( bus_ready				),
		.bus_wdata			( bus_wdata				),
		.bus_address		( bus_address			),
		.bus_rdata			( bus_rdata				),
		.bus_rdata_en		( bus_rdata_en			),
		.z80_active			( z80_active			),
		.r800_active		( r800_active			),
		.processor_mode		( processor_mode		),
		.cpu_sel			( cpu_sel				)
	);

	initial begin
		clk = 1'b0;
		forever #( c_clk_period / 2.0 ) clk = ~clk;
	end

	//	run_ack モデル: run_req = 0 が続いた ack_delay サイクル後に run_ack = 0 を返す
	always @( posedge clk ) begin
		if( !reset_n || z80_run_req ) begin
			z80_run_ack		<= 1'b1;
			z80_ack_counter	<= 0;
		end
		else if( z80_ack_counter < z80_ack_delay ) begin
			z80_ack_counter	<= z80_ack_counter + 1;
		end
		else begin
			z80_run_ack		<= 1'b0;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n || r800_run_req ) begin
			r800_run_ack	<= 1'b1;
			r800_ack_counter<= 0;
		end
		else if( r800_ack_counter < r800_ack_delay ) begin
			r800_ack_counter<= r800_ack_counter + 1;
		end
		else begin
			r800_run_ack	<= 1'b0;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n || pico_run_req ) begin
			pico_run_ack	<= 1'b1;
			pico_ack_counter<= 0;
		end
		else if( pico_ack_counter < pico_ack_delay ) begin
			pico_ack_counter<= pico_ack_counter + 1;
		end
		else begin
			pico_run_ack	<= 1'b0;
		end
	end

	task automatic check;
		input condition;
		input [8*96-1:0] message;
		begin
			if( condition ) begin
				$display( "PASS: %0s", message );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "FAIL: %0s", message );
				fail_count = fail_count + 1;
			end
		end
	endtask

	task automatic device_write_reg;
		input [1:0] address;
		input [7:0] data;
		begin
			while( !bus_ready ) begin
				@( posedge clk );
			end
			@( posedge clk );
			bus_cs		<= 1'b1;
			bus_write	<= 1'b1;
			bus_valid	<= 1'b1;
			bus_address	<= address;
			bus_wdata	<= data;
			@( posedge clk );
			bus_cs		<= 1'b0;
			bus_write	<= 1'b0;
			bus_valid	<= 1'b0;
			bus_address	<= 2'd0;
			bus_wdata	<= 8'd0;
		end
	endtask

	//	レジスタ index=6 に書き込み、cpu_change_target ビット(bit5)を発行する
	task automatic request_cpu_change;
		input target_r800;
		begin
			device_write_reg( 2'd0, 8'd6 );
			device_write_reg( 2'd1, target_r800 ? 8'h20 : 8'h00 );
		end
	endtask

	//	pico_change_req を1クロックだけパルスさせる
	task automatic request_pico_change;
		input target_pico;
		begin
			@( posedge clk );
			pico_change_target	<= target_pico;
			pico_change_req		<= 1'b1;
			@( posedge clk );
			pico_change_req		<= 1'b0;
		end
	endtask

	task automatic wait_cpu_sel;
		input [1:0] expected_sel;
		integer timeout;
		begin
			timeout = 0;
			while( cpu_sel != expected_sel && timeout < 200 ) begin
				@( posedge clk );
				timeout = timeout + 1;
			end
			check( cpu_sel == expected_sel, "cpu_sel changed to requested value" );
		end
	endtask

	//	cpu_select が ST_CHANGING (=1) に入るまで待つ (階層参照で内部状態を直接確認)
	task automatic wait_changing;
		integer timeout;
		begin
			timeout = 0;
			while( ( u_dut.u_cpu_select.ff_state0 !== 1'b1 ) && ( u_dut.u_cpu_select.ff_state1 !== 1'b1 ) && timeout < 200 ) begin
				@( posedge clk );
				timeout = timeout + 1;
			end
			check( ( u_dut.u_cpu_select.ff_state0 === 1'b1 ) || ( u_dut.u_cpu_select.ff_state1 === 1'b1 ), "cpu_select entered CHANGING state" );
		end
	endtask

	//	レジスタ側の cpu_change_req が下がりきるまで待つ (次のリクエストとの衝突を避ける)
	task automatic settle;
		begin
			repeat( 8 ) @( posedge clk );
		end
	endtask

	initial begin
		pass_count			= 0;
		fail_count			= 0;
		reset_n				= 1'b0;
		cpu_pause			= 1'b0;
		z80_run_ack			= 1'b1;
		r800_run_ack		= 1'b1;
		pico_run_ack		= 1'b1;
		pico_change_req		= 1'b0;
		pico_change_target	= 1'b0;
		bus_cs				= 1'b0;
		bus_write			= 1'b0;
		bus_valid			= 1'b0;
		bus_wdata			= 8'd0;
		bus_address			= 2'd0;
		z80_ack_delay		= 2;
		r800_ack_delay		= 3;
		pico_ack_delay		= 4;
		z80_ack_counter		= 0;
		r800_ack_counter	= 0;
		pico_ack_counter	= 0;

		repeat( 8 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 2 ) @( posedge clk );

		check( cpu_sel == 2'b00, "reset selects Z80 (cpu_sel=00)" );
		check( z80_active && !r800_active, "z80_active only after reset" );
		check( processor_mode == 1'b0, "processor_mode=0 for Z80" );
		check( z80_run_req == 1'b1 && r800_run_req == 1'b0 && pico_run_req == 1'b0,
				"only z80_run_req is released after reset" );

		// ---------------------------------------------------------
		//	register 経由の CPU 切替: Z80 -> R800
		// ---------------------------------------------------------
		request_cpu_change( 1'b1 );
		wait_changing();
		check( z80_run_req == 1'b0 && r800_run_req == 1'b0 && pico_run_req == 1'b0,
				"all run_req deasserted while changing to R800" );
		wait_cpu_sel( 2'b01 );
		check( z80_active == 1'b0 && r800_active == 1'b1, "r800_active after switch" );
		check( processor_mode == 1'b1, "processor_mode=1 for R800" );
		check( z80_run_req == 1'b0 && r800_run_req == 1'b1 && pico_run_req == 1'b0,
				"only r800_run_req is released after switching to R800" );
		settle();

		// ---------------------------------------------------------
		//	register 経由の CPU 切替: R800 -> Z80
		// ---------------------------------------------------------
		request_cpu_change( 1'b0 );
		wait_changing();
		check( z80_run_req == 1'b0 && r800_run_req == 1'b0 && pico_run_req == 1'b0,
				"all run_req deasserted while changing to Z80" );
		wait_cpu_sel( 2'b00 );
		check( z80_active == 1'b1 && r800_active == 1'b0, "z80_active after switch back" );
		check( processor_mode == 1'b0, "processor_mode=0 for Z80" );
		settle();

		// ---------------------------------------------------------
		//	Pico 切替: Z80 -> Pico (戻り先 Z80)
		// ---------------------------------------------------------
		request_pico_change( 1'b1 );
		wait_changing();
		wait_cpu_sel( 2'b10 );
		check( z80_active == 1'b0 && r800_active == 1'b0, "neither CPU active while PICO runs" );
		check( pico_run_req == 1'b1 && z80_run_req == 1'b0 && r800_run_req == 1'b0,
				"only pico_run_req is released while PICO runs" );
		settle();

		// ---------------------------------------------------------
		//	Pico 切替: Pico -> Z80 (戻り先が保持されている)
		// ---------------------------------------------------------
		request_pico_change( 1'b0 );
		wait_changing();
		wait_cpu_sel( 2'b00 );
		check( z80_active == 1'b1, "returns to Z80 after releasing PICO" );
		settle();

		// ---------------------------------------------------------
		//	Pico 切替: R800 -> Pico -> R800 (戻り先が保持されている)
		// ---------------------------------------------------------
		request_cpu_change( 1'b1 );
		wait_changing();
		wait_cpu_sel( 2'b01 );
		settle();

		request_pico_change( 1'b1 );
		wait_changing();
		wait_cpu_sel( 2'b11 );
		check( pico_run_req == 1'b1 && z80_run_req == 1'b0 && r800_run_req == 1'b0,
				"only pico_run_req is released while PICO runs (from R800)" );
		settle();

		request_pico_change( 1'b0 );
		wait_changing();
		wait_cpu_sel( 2'b01 );
		check( r800_active == 1'b1, "returns to R800 after releasing PICO" );
		settle();

		// ---------------------------------------------------------
		//	cpu_pause = 1 の間はすべての run_req = 0 になる
		// ---------------------------------------------------------
		cpu_pause = 1'b1;
		@( posedge clk );
		check( z80_run_req == 1'b0 && r800_run_req == 1'b0 && pico_run_req == 1'b0,
				"all run_req deasserted while cpu_pause is active" );
		repeat( 4 ) @( posedge clk );
		check( z80_run_req == 1'b0 && r800_run_req == 1'b0 && pico_run_req == 1'b0,
				"all run_req remain deasserted during cpu_pause" );
		cpu_pause = 1'b0;
		@( posedge clk );
		check( z80_run_req == 1'b0 && r800_run_req == 1'b1 && pico_run_req == 1'b0,
				"run_req returns to the selected CPU after cpu_pause is released" );

		$display( "============================================================" );
		$display( "Results: PASS = %0d, FAIL = %0d", pass_count, fail_count );
		if( fail_count == 0 ) begin
			$display( "All tests PASSED." );
		end
		else begin
			$display( "Some tests FAILED." );
		end
		$finish;
	end
endmodule
