// -----------------------------------------------------------------------------
//	cz80_inst / cr800_inst のカートリッジ向けメモリ書き込み波形テスト
//	slot_d (slot_d_oe) が /WR の立下りより先に出て、立上りより後で解放されることを確認する。
// -----------------------------------------------------------------------------

`timescale 1ps/1ps

module tb;
	wire rfsh_n;
	reg [15:0] refresh_address;
	reg previous_rfsh_n = 1'b1;
	integer refresh_checks = 0;
	integer sampled_state_count;
	localparam	clk_base = 1_000_000_000 / 42_955;	//	ps (42.954545MHz)

	reg				clk = 1'b0;
	reg				reset_n = 1'b0;
	reg		[3:0]	state_count = 4'd0;
	wire			wr_n;
	wire			iorq_n;
	wire			rd_n;
	wire			m1_n;
	wire			merq_n;
	wire			slot_d_oe;
	tri	[7:0]	slot_d;
	wire	[7:0]	bus_wdata;
	wire	[15:0]	bus_address;
	reg		[7:0]	rom [0:255];
	reg		[7:0]	bus_rdata = 8'h00;
	reg				bus_rdata_en = 1'b0;
	reg				bus_ready = 1'b0;
	wire			bus_valid;
	wire			bus_write;
	wire			bus_io;
	integer			data_lead_ps;
	integer			data_hold_ps;
	reg	[7:0]	bus_wdata_at_assert;
	reg	[7:0]	slot_data_at_assert;
	time			data_assert_time;
	time			data_release_time;
	time			wr_fall_time;
	time			wr_rise_time;

	always #(clk_base/2) clk = ~clk;

	//	/MERQ 立下りから21カウント(約489ns)後にデータが出る遅いROMモデル
	reg				slot_valid = 1'b0;
	always @( negedge merq_n ) begin
		slot_valid = 1'b0;
		#( clk_base * 21 );
		slot_valid = !merq_n;
	end
	always @( posedge merq_n ) slot_valid = 1'b0;
	assign slot_d = slot_d_oe ? bus_wdata : 8'bz;
	assign slot_d = ( slot_valid && !rd_n && wr_n ) ? 8'hA5 : 8'bz;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			state_count <= 4'd0;
		end
		else if( state_count == 4'd11 ) begin
			state_count <= 4'd0;
		end
		else begin
			state_count <= state_count + 4'd1;
		end
	end

	cz80_inst u_cz80_inst (
		.reset_n		( reset_n		),
		.clk			( clk			),
		.state_count	( state_count	),
		.int_n			( 1'b1			),
		.nmi_n			( 1'b1			),
		.wait_n			( 1'b1			),
		.m1_n			( m1_n			),
		.merq_n			( merq_n		),
		.iorq_n			( iorq_n		),
		.rd_n			( rd_n			),
		.wr_n			( wr_n			),
		.slot_d_oe		( slot_d_oe		),
		.rfsh_n			( rfsh_n		),
		.run_req		( 1'b1			),
		.run_ack		(				),
		.slot_d			( slot_d		),
		.bus_io			( bus_io		),
		.bus_write		( bus_write		),
		.bus_valid		( bus_valid		),
		.bus_ready		( bus_ready		),
		.bus_address	( bus_address	),
		.bus_wdata		( bus_wdata		),
		.bus_rdata		( bus_rdata		),
		.bus_rdata_en	( bus_rdata_en	),
		.pc				(				),
		.int_ack		(				)
	);

	always @( posedge clk ) begin
		sampled_state_count = state_count;
		if( reset_n && u_cz80_inst.ff_run && !u_cz80_inst.w_rfsh_n && !u_cz80_inst.ff_bus_m1_n && u_cz80_inst.w_t_state == 3'd3 && state_count == 4'd2 ) begin
			refresh_address = u_cz80_inst.w_bus_address;
		end
		#1;
		if( reset_n && !rfsh_n ) begin
			if( previous_rfsh_n && sampled_state_count != 4 ) begin
				$fatal( 1, "Refresh did not start at count 4" );
			end
			if( bus_address !== refresh_address ) begin
				$fatal( 1, "Refresh address changed: expected %04h, got %04h", refresh_address, bus_address );
			end
			refresh_checks = refresh_checks + 1;
		end
		previous_rfsh_n = rfsh_n;
	end

	always @( posedge merq_n ) begin
		#1;
		if( reset_n && !m1_n && !rd_n ) begin
			$fatal( 1, "M1 /MERQ rises after /RD" );
		end
	end

	always @( posedge rd_n ) begin
		#1;
		if( reset_n && !m1_n && !merq_n ) begin
			$fatal( 1, "M1 /RD rises before /MERQ" );
		end
	end

	always @( negedge rd_n ) begin
		#1;
		if( reset_n && m1_n && iorq_n && merq_n ) begin
			$fatal( 1, "Memory /RD falls before /MERQ" );
		end
	end

	//	命令フェッチに応答するだけの簡易ROMモデル (書き込みは受理のみ)
	always @( posedge clk ) begin
		if( !reset_n ) begin
			bus_ready		<= 1'b0;
			bus_rdata_en	<= 1'b0;
		end
		else begin
			bus_ready		<= 1'b0;
			bus_rdata_en	<= 1'b0;
			if( bus_valid ) begin
				if( bus_write ) begin
					bus_ready	<= 1'b1;
				end
				else if( bus_io || bus_address[7:0] != 8'h80 ) begin
					bus_rdata		<= bus_io ? 8'hFF : rom[bus_address[7:0]];
					bus_rdata_en	<= 1'b1;
				end
			end
		end
	end

	always @( posedge slot_d_oe ) begin
		data_assert_time = $time;
		#1;
		bus_wdata_at_assert = bus_wdata;
		slot_data_at_assert = slot_d;
	end
	always @( negedge slot_d_oe ) data_release_time = $time;
	always @( negedge wr_n ) wr_fall_time = $time;
	always @( posedge wr_n ) if( reset_n ) wr_rise_time = $time;

	initial begin
		rom[0] = 8'h3E;	rom[1] = 8'h5A;				//	LD A,5Ah
		rom[2] = 8'h32;	rom[3] = 8'h80;	rom[4] = 8'h00;	//	LD (0080h),A
		rom[5] = 8'hD3;	rom[6] = 8'h98;				//	OUT (98h),A
		rom[7] = 8'h3A;	rom[8] = 8'h80;	rom[9] = 8'h00;	//	LD A,(0080h)
		rom[10] = 8'hC3;	rom[11] = 8'h02;	rom[12] = 8'h00;	//	JP 0002h

		repeat( 4 ) @( posedge clk );
		reset_n = 1'b1;

		check_write( "cz80 memory", 1'b0, 100000 );
		check_write( "cz80 I/O", 1'b1, 50000 );
		check_data_read();
		if( refresh_checks == 0 ) begin
			$fatal( 1, "No refresh address checks" );
		end
		$display( "PASS: cz80 refresh address held throughout /RFSH Low (%0d checks)", refresh_checks );
		$finish;
	end

	//	データ用メモリリードはスロットから読み、/MERQ 幅を測る
	task check_data_read();
		time merq_fall_time;
		integer merq_width_ps;
		@( negedge merq_n iff ( m1_n && bus_address == 16'h0080 && wr_n ) );
		merq_fall_time = $time;
		@( posedge merq_n );
		merq_width_ps = $time - merq_fall_time;
		#( clk_base * 24 );
		$display( "[cz80 data read] /MERQ width = %0d ps, A = %02h", merq_width_ps, u_cz80_inst.u_cz80.acc );
		if( u_cz80_inst.u_cz80.acc !== 8'hA5 ) begin
			$fatal( 1, "cz80 data read: T3 中ほどで slot_d を取り込めていない" );
		end
		$display( "PASS: cz80 data read latches slot_d in the middle of T3" );
	endtask

	task check_write( input string name, input logic is_io, input integer min_lead_ps );
		@( negedge wr_n );
		if( (iorq_n == 1'b0) != is_io ) begin
			$fatal( 1, "%s: 想定と異なる書き込みサイクル", name );
		end
		@( posedge wr_n );
		#( clk_base * 8 );
		data_lead_ps = wr_fall_time - data_assert_time;
		data_hold_ps = data_release_time - wr_rise_time;
		$display( "[%s] data lead = %0d ps, data hold = %0d ps", name, data_lead_ps, data_hold_ps );
		if( bus_wdata_at_assert !== 8'h5A || slot_data_at_assert !== 8'h5A ) begin
			$fatal( 1, "%s: expected 5Ah at slot_d_oe; bus_wdata=%02h slot_d=%02h", name, bus_wdata_at_assert, slot_data_at_assert );
		end
		if( data_lead_ps < min_lead_ps || data_hold_ps < 50000 ) begin
			$fatal( 1, "%s: slot_d が /WR を包含していない", name );
		end
		$display( "PASS: %s write drives slot_d before /WR and releases it after /WR", name );
	endtask
endmodule

module tb_cr800_slot_write;
	localparam	clk_base = 1_000_000_000 / 42_955;

	reg				clk = 1'b0;
	reg				reset_n = 1'b0;
	reg		[3:0]	state_count = 4'd0;
	wire			wr_n;
	wire			iorq_n;
	wire			slot_d_oe;
	wire	[15:0]	bus_address;
	wire			bus_valid;
	wire			bus_write;
	wire			bus_io;
	reg		[7:0]	rom [0:255];
	reg		[7:0]	slot_data = 8'hFF;
	integer			data_lead_ps;
	integer			data_hold_ps;
	time			data_assert_time;
	time			data_release_time;
	time			wr_fall_time;
	time			wr_rise_time;

	always #(clk_base/2) clk = ~clk;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			state_count <= 4'd0;
		end
		else if( state_count == 4'd11 ) begin
			state_count <= 4'd0;
		end
		else begin
			state_count <= state_count + 4'd1;
		end
	end

	//	SLOT#1/#2 を対象にするため slot12_cs を 1 に固定する
	cr800_inst u_cr800_inst (
		.reset_n		( reset_n		),
		.clk			( clk			),
		.state_count	( state_count	),
		.int_n			( 1'b1			),
		.nmi_n			( 1'b1			),
		.wait_n			( 1'b1			),
		.m1_n			(				),
		.merq_n			(				),
		.iorq_n			( iorq_n		),
		.rd_n			(				),
		.wr_n			( wr_n			),
		.slot_d_oe		( slot_d_oe		),
		.rfsh_n			(				),
		.run_req		( 1'b1			),
		.run_ack		(				),
		.slot_d			( slot_data		),
		.flash_cs		( 1'b0			),
		.main_rom_cs	( 1'b0			),
		.slot12_cs		( 1'b1			),
		.ssram_access	( 1'b0			),
		.bus_io			( bus_io		),
		.bus_write		( bus_write		),
		.bus_valid		( bus_valid		),
		.bus_ready		( 1'b0			),
		.bus_address	( bus_address	),
		.bus_wdata		(				),
		.bus_rdata		( 8'hFF			),
		.bus_rdata_en	( 1'b0			),
		.pc				(				),
		.int_ack		(				)
	);

	//	SLOT 経由の読み出しは slot_d でのみ応答する
	always @( * ) slot_data = rom[bus_address[7:0]];

	always @( posedge slot_d_oe ) data_assert_time = $time;
	always @( negedge slot_d_oe ) data_release_time = $time;
	always @( negedge wr_n ) wr_fall_time = $time;
	always @( posedge wr_n ) if( reset_n ) wr_rise_time = $time;

	initial begin
		rom[0] = 8'h3E;	rom[1] = 8'h5A;
		rom[2] = 8'h32;	rom[3] = 8'h80;	rom[4] = 8'h00;
		rom[5] = 8'hD3;	rom[6] = 8'h98;
		rom[7] = 8'hC3;	rom[8] = 8'h02;	rom[9] = 8'h00;

		repeat( 4 ) @( posedge clk );
		reset_n = 1'b1;

		check_write( "cr800 cartridge memory", 1'b0, 100000 );
		check_write( "cr800 external I/O", 1'b1, 50000 );
		$finish;
	end

	task check_write( input string name, input logic is_io, input integer min_lead_ps );
		@( negedge wr_n );
		if( (iorq_n == 1'b0) != is_io ) begin
			$fatal( 1, "%s: 想定と異なる書き込みサイクル", name );
		end
		@( posedge wr_n );
		#( clk_base * 8 );
		data_lead_ps = wr_fall_time - data_assert_time;
		data_hold_ps = data_release_time - wr_rise_time;
		$display( "[%s] data lead = %0d ps, data hold = %0d ps", name, data_lead_ps, data_hold_ps );
		if( data_lead_ps < min_lead_ps || data_hold_ps < 50000 ) begin
			$fatal( 1, "%s: slot_d が /WR を包含していない", name );
		end
		$display( "PASS: %s write drives slot_d before /WR and releases it after /WR", name );
	endtask
endmodule
