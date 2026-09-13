// -----------------------------------------------------------------------------
//	ip_spi_rom.v
//	Copyright (C)2026 Takayuki Hara (HRA!)
//	
//	 Permission is hereby granted, free of charge, to any person obtaining a 
//	copy of this software and associated documentation files (the "Software"), 
//	to deal in the Software without restriction, including without limitation 
//	the rights to use, copy, modify, merge, publish, distribute, sublicense, 
//	and/or sell copies of the Software, and to permit persons to whom the 
//	Software is furnished to do so, subject to the following conditions:
//	
//	The above copyright notice and this permission notice shall be included in 
//	all copies or substantial portions of the Software.
//	
//	The Software is provided "as is", without warranty of any kind, express or 
//	implied, including but not limited to the warranties of merchantability, 
//	fitness for a particular purpose and noninfringement. In no event shall the 
//	authors or copyright holders be liable for any claim, damages or other 
//	liability, whether in an action of contract, tort or otherwise, arising 
//	from, out of or in connection with the Software or the use or other dealings 
//	in the Software.
// -----------------------------------------------------------------------------
//	Description:
//		SPI serial flash ROM controller
// -----------------------------------------------------------------------------

module ip_spi_rom(
	input			reset,				//	System Reset (Active High)
	input			clk,				//	System Clock
	input			clk_serial,			//	Serial Clock (High speed)
	//	Internal BUS interface
	input			bus_cs,
	input			bus_address,
	input			bus_write,
	input			bus_valid,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	//	SPI interface
	output			srom0_cs_n,
	output			srom1_cs_n,
	output			srom_clk,
	inout			srom_hold_n,
	inout			srom_wp_n,
	inout			srom_do,
	inout			srom_di
);
	localparam	[2:0]	MODE_STD_WRITE				= 3'd0;
	localparam	[2:0]	MODE_STD_READ				= 3'd1;

	localparam	[7:0]	SROM_PAGE_PROGRAM			= 8'h02;
	localparam	[7:0]	SROM_WRITE_DISABLE			= 8'h04;
	localparam	[7:0]	SROM_READ_STATUS_1			= 8'h05;
	localparam	[7:0]	SROM_READ_STATUS_2			= 8'h35;
	localparam	[7:0]	SROM_WRITE_ENABLE			= 8'h06;
	localparam	[7:0]	SROM_BLOCK_ERASE			= 8'hD8;
	localparam	[7:0]	SROM_CHIP_ERASE				= 8'h60;
	localparam	[7:0]	SROM_FAST_READ				= 8'h0B;

	localparam	[3:0]	CMD_SET_ADDRESS				= 4'd0;
	localparam	[3:0]	CMD_SINGLE_READ				= 4'd1;
	localparam	[3:0]	CMD_BURST_READ				= 4'd2;
	localparam	[3:0]	CMD_BURST_WRITE				= 4'd3;
	localparam	[3:0]	CMD_CHIP_ERASE				= 4'd4;
	localparam	[3:0]	CMD_READ_STATUS				= 4'd5;
	localparam	[3:0]	CMD_SELECT_SROM				= 4'd6;
	localparam	[3:0]	CMD_ACCESS_END				= 4'd7;
	localparam	[3:0]	CMD_WRITE_ENABLE			= 4'd8;
	localparam	[3:0]	CMD_BLOCK_ERASE				= 4'd9;
	localparam	[3:0]	CMD_READ_STATUS_2			= 4'd10;
	localparam	[3:0]	CMD_NOP						= 4'd15;

	
	reg				ff_bus_ready;
	reg		[7:0]	ff_bus_rdata;
	reg				ff_bus_rdata_en;

	reg		[3:0]	ff_command_mode;
	reg		[23:0]	ff_rom_address;
	reg		[1:0]	ff_byte_count;
	reg		[7:0]	ff_burst_wdata;
	reg		[7:0]	ff_burst_count;
	reg				ff_do_command;
	reg				ff_finish_command;

	reg		[2:0]	ff_serial_mode;
	reg		[7:0]	ff_serial_wdata;
	reg				ff_serial_write;
	reg				ff_serial_valid;
	wire			w_serial_ready;
	wire	[7:0]	w_serial_rdata;
	wire			w_serial_rdata_en;
	wire			w_serial_idle;
	reg				ff_srom0_cs_n;
	reg				ff_srom1_cs_n;
	reg				ff_cs_n;

	localparam [2:0]	CS_WAIT_10NS	= 1;
	localparam [2:0]	CS_WAIT_50NS	= 5;
	reg		[2:0]		ff_wait_count;
	reg					ff_wait_count_active;

	// ---------------------------------------------------------
	//	Inlined SPI controller state
	// ---------------------------------------------------------
	reg		[2:0]	ff_fifo_mode;
	reg		[7:0]	ff_fifo_wdata;
	reg				ff_fifo_write;
	reg				ff_fifo_valid;
	reg		[2:0]	ff_xfer_mode;
	reg		[7:0]	ff_xfer_wdata;
	reg				ff_xfer_write;
	reg				ff_xfer_valid;
	reg				ff_xfer_ready;
	reg		[7:0]	ff_xfer_rdata;
	reg				ff_xfer_rdata_en;
	reg				ff_xfer_processing;
	reg				ff_xfer_spi_accepted;

	localparam	[4:0]	ST_SPI_IDLE			= 5'd0;
	localparam	[4:0]	ST_SPI_STD_WRITE		= 5'd1;
	localparam	[4:0]	ST_SPI_STD_WRITE_CLK	= 5'd2;
	localparam	[4:0]	ST_SPI_STD_READ		= 5'd3;
	localparam	[4:0]	ST_SPI_STD_READ_CLK	= 5'd4;
	localparam	[4:0]	ST_SPI_STD_READ_LOOP	= 5'd5;
	localparam	[4:0]	ST_SPI_FINISH			= 5'd6;

	reg				ff_spi_serial_valid0;
	reg				ff_spi_serial_valid1;
	reg				ff_spi_processing;
	reg				ff_spi_ce;
	reg		[4:0]	ff_spi_state;
	reg		[2:0]	ff_spi_substate;
	reg				ff_spi_clk;
	reg		[7:0]	ff_spi_data;
	reg		[3:0]	ff_spi_hiz;
	reg		[3:0]	ff_spi_sio;
	reg		[7:0]	ff_spi_rdata;
	wire	[3:0]	w_srom_sio;

	// ---------------------------------------------------------
	//	bus_address
	//		0: command port
	//		1: data port
	//
	//	command port:
	//		0x00: set address mode
	//			0x00を書き込むと 24bit のアドレスをセットするモード
	//			になる。この後に続けて data port へ、3byte 書き込む
	//			と、その値がアドレスとしてセットされる。
	//			3byte は、MSB から順に書き込む。
	//			1byte, 2byte しか書き込んでない状態で、command port
	//			に 0x00 を書き込むと、また 1byte目からに戻る。
	//		0x01: single read mode
	//			1byte の読み出しを行うモード。読み出しは、data port から行う。
	//			このモードでは、アドレスは自動でインクリメントされる。
	//			アドレスは、set address mode を使う。
	//			Serial ROM に対しては、data port からの読み出しのたびに
	//			アドレスをセットしに行く。
	//		0x02: burst read mode
	//			256byte の読み出しを行うモード。0x02 を書いた時点でアドレスを
	//			発行し、その後の data port からの読み出しは、
	//			1byte 読み出しのみである。
	//			開始アドレスは、アドレスの下位 1byte が無視される。
	//		0x03: burst write mode
	//			256byte の書き込みを行うモード。0x03 を書いた時点でアドレスを
	//			発行し、その後の data port への書き込みは、
	//			1byte 書き込みのみである。
	//			開始アドレスは、アドレスの下位 1byte が無視される。
	//		0x04: chip erase
	//			Serial ROM 全体を消去するコマンドを発行する。
	//			このモードでは、data port へのアクセスは行わない。
	//		0x05: read status register
	//			Serial ROM のステータスレジスタを読み出すモード。
	//			data port から、1byte 読み出すと、その最下位に busy ステータス
	//			が入る。
	//		0x06: select serial ROM
	//			このモードでは、接続する Serial ROM を選択する。
	//			data port へ Serial ROM 番号を書き込むと、その Serial ROM を選択する。
	//			0x00: srom0_cs_n をアクティブにする
	//			0x01: srom1_cs_n をアクティブにする
	//			0x02-0xFE: reserved
	//			0xFF: 未接続
	//		0x07: access end
	//			w_serial_idle が 1 になるのを待ってから、ff_cs_n を 1 に戻す。
	//		0x08: write enable
	//			Serial ROM へ WRITE_ENABLE(06h) のみを発行する。
	//		0x09: block erase
	//			Serial ROM へ BLOCK_ERASE(D8h) + 24bit address を発行する。
	//			address は set address mode で設定した値を使う。
	//		0x0A: read status register 2
	//			Serial ROM のステータスレジスタ2を読み出すモード。
	//			data port から、1byte 読み出すと、その最下位bitが入る。
	//		0x0B-0xFF: reserved
	// ---------------------------------------------------------
	//	SerialROM Status Register
	//	S0: busy
	//	S1: write enable latch
	//	S2: block protect bit 0
	//	S3: block protect bit 1
	//	S4: block protect bit 2
	//	S5: top/bottom write protect
	//	S6: sector protect
	//	S7: status register protect 0
	//	S8: status register protect 1
	//	S9-15: reserved
	// ---------------------------------------------------------

	// ---------------------------------------------------------
	//	Register interface
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( reset ) begin
			ff_command_mode			<= CMD_SET_ADDRESS;
			ff_srom0_cs_n			<= 1'b1;
			ff_srom1_cs_n			<= 1'b1;
			ff_bus_ready			<= 1'b1;
			ff_do_command			<= 1'b0;
			ff_burst_wdata			<= 8'd0;
			ff_burst_count			<= 8'd0;
		end
		else if( !ff_bus_ready ) begin
			ff_do_command			<= 1'b0;
			if( ff_finish_command && ((ff_command_mode == CMD_SINGLE_READ) || (ff_command_mode == CMD_BURST_READ) || (ff_command_mode == CMD_BURST_WRITE)) ) begin
				ff_rom_address	<= ff_rom_address + 24'd1;
			end
			if( ff_finish_command && (!ff_cs_n || (ff_wait_count == 0)) ) begin
				ff_bus_ready		<= 1'b1;
			end
		end
		else if( bus_cs && bus_valid ) begin
			if( (bus_address == 1'b0) && bus_write ) begin
				//	command port
				case( bus_wdata )
					8'h00: begin
						//	set address mode
						ff_command_mode	<= CMD_SET_ADDRESS;
						ff_byte_count	<= 2'd0;
					end
					8'h01: begin
						//	single read mode
						ff_command_mode	<= CMD_SINGLE_READ;
					end
					8'h02: begin
						//	burst read mode
						ff_command_mode	<= CMD_BURST_READ;
					end
					8'h03: begin
						//	burst write mode
						ff_command_mode			<= CMD_BURST_WRITE;
						ff_rom_address[7:0]		<= 8'h00;
						ff_burst_count			<= 8'd0;
					end
					8'h04: begin
						//	chip erase
						ff_command_mode			<= CMD_CHIP_ERASE;
					end
					8'h05: begin
						//	read status register
						ff_command_mode			<= CMD_READ_STATUS;
					end
					8'h06: begin
						//	select serial ROM
						ff_command_mode			<= CMD_SELECT_SROM;
					end
					8'h07: begin
						//	access end
						ff_command_mode			<= CMD_ACCESS_END;
						ff_bus_ready			<= 1'b0;
						ff_do_command			<= 1'b1;
					end
					8'h08: begin
						//	write enable
						ff_command_mode			<= CMD_WRITE_ENABLE;
						ff_bus_ready			<= 1'b0;
						ff_do_command			<= 1'b1;
					end
					8'h09: begin
						//	block erase
						ff_command_mode			<= CMD_BLOCK_ERASE;
						ff_bus_ready			<= 1'b0;
						ff_do_command			<= 1'b1;
					end
					8'h0A: begin
						//	read status register 2
						ff_command_mode			<= CMD_READ_STATUS_2;
					end
					default: begin
						//	reserved command: enter NOP mode to avoid stale mode side effects.
						ff_command_mode	<= CMD_NOP;
					end
				endcase
			end
			else if( (bus_address == 1'b1) && bus_write ) begin
				//	data port
				case( ff_command_mode )
					CMD_SET_ADDRESS: begin
						case( ff_byte_count )
							2'd0: begin
								ff_rom_address[ 7: 0]	<= bus_wdata;
								ff_byte_count			<= 2'd1;
							end
							2'd1: begin
								ff_rom_address[15: 8]	<= bus_wdata;
								ff_byte_count			<= 2'd2;
							end
							2'd2: begin
								ff_rom_address[23:16]	<= bus_wdata;
								ff_byte_count			<= 2'd0;
							end
							default: begin
								//	invalid operation
							end
						endcase
					end
					CMD_BURST_WRITE: begin
						//	data port への書き込みは、burst write で 1byte ずつ送る。
						if( ff_cs_n ) begin
							//	初回の burst write の場合は、ff_cs_n = 1 なので、コマンド発行処理を実施。
							ff_burst_wdata			<= bus_wdata;
							ff_bus_ready			<= 1'b0;
							ff_do_command			<= 1'b1;
						end
						else begin
							//	2回目以降の burst write の場合は、ff_cs_n = 0 なので、コマンド発行処理は不要。
							ff_burst_wdata			<= bus_wdata;
							ff_bus_ready			<= 1'b0;
							ff_burst_count			<= ff_burst_count + 8'd1;
							ff_do_command			<= 1'b1;
						end
					end
					CMD_CHIP_ERASE: begin
						//	このモードでは、data port へのアクセスは行わない。
						ff_bus_ready			<= 1'b0;
						ff_do_command			<= 1'b1;
					end
					CMD_SELECT_SROM: begin
						//	data port へ Serial ROM 番号を書き込むと、その Serial ROM を選択する。
						case( bus_wdata )
							8'h00: begin
								//	srom0_cs_n をアクティベートする
								ff_srom0_cs_n <= 1'b0;
								ff_srom1_cs_n <= 1'b1;
							end
							8'h01: begin
								//	srom1_cs_n をアクティベートする
								ff_srom0_cs_n <= 1'b1;
								ff_srom1_cs_n <= 1'b0;
							end
							default: begin
								//	未接続にする
								ff_srom0_cs_n <= 1'b1;
								ff_srom1_cs_n <= 1'b1;
							end
						endcase
					end
					default: begin
						//	reserved command, do nothing.
					end
				endcase
			end
			else if( (bus_address == 1'b1) && !bus_write ) begin
				case( ff_command_mode )
					CMD_SINGLE_READ: begin
						//	Serial ROM に対しては、data port からの読み出しのたびにアドレスをセットしに行く。
						ff_bus_ready		<= 1'b0;
						ff_do_command		<= 1'b1;
					end
					CMD_BURST_READ: begin
						//	0x02 を書いた時点でアドレスを発行し、その後の data port からの読み出しは、1byte 読み出しのみである。
						ff_bus_ready		<= 1'b0;
						ff_do_command		<= 1'b1;
					end
					CMD_READ_STATUS: begin
						//	data port から、1byte 読み出すと、その最下位に busy ステータスが入る。
						ff_bus_ready		<= 1'b0;
						ff_do_command		<= 1'b1;
					end
					CMD_READ_STATUS_2: begin
						//	data port から、1byte 読み出すと、その最下位bitが入る。
						ff_bus_ready		<= 1'b0;
						ff_do_command		<= 1'b1;
					end
					default: begin
						//	reserved command, do nothing.
					end
				endcase
			end
		end
	end

	assign bus_ready	= ff_bus_ready;
	assign bus_rdata	= ff_bus_rdata;
	assign bus_rdata_en	= ff_bus_rdata_en;

	// ---------------------------------------------------------
	//	コマンド実行ステートマシン
	// ---------------------------------------------------------
	localparam	[4:0]	ST_IDLE					= 5'd0;
	localparam	[4:0]	ST_READ_BYTE			= 5'd1;
	localparam	[4:0]	ST_RECEIVE_BYTE			= 5'd2;
	localparam	[4:0]	ST_WAIT					= 5'd3;
	localparam	[4:0]	ST_WRITE_MODE			= 5'd4;
	localparam	[4:0]	ST_WRITE_ADDR_H			= 5'd5;
	localparam	[4:0]	ST_WRITE_ADDR_M			= 5'd6;
	localparam	[4:0]	ST_WRITE_ADDR_L			= 5'd7;
	localparam	[4:0]	ST_WRITE_BYTE			= 5'd8;
	localparam	[4:0]	ST_ERASE				= 5'd9;
	localparam	[4:0]	ST_FINISH				= 5'd10;
	localparam	[4:0]	ST_READ_MODE			= 5'd11;
	localparam	[4:0]	ST_READ_ADDR_H			= 5'd12;
	localparam	[4:0]	ST_READ_ADDR_M			= 5'd13;
	localparam	[4:0]	ST_READ_ADDR_L			= 5'd14;
	localparam	[4:0]	ST_READ_DUMMY			= 5'd15;
	localparam	[4:0]	ST_BLOCK_ERASE_ADDR_H	= 5'd16;
	localparam	[4:0]	ST_BLOCK_ERASE_ADDR_M	= 5'd17;
	localparam	[4:0]	ST_BLOCK_ERASE_ADDR_L	= 5'd18;

	reg		[4:0]		ff_command_state;
	reg		[4:0]		ff_next_command_state;

	always @( posedge clk ) begin
		if( reset ) begin
			ff_wait_count	<= 0;
		end
		else if( ff_cs_n == 1'b0 ) begin
			if( ff_command_mode == CMD_BURST_READ || ff_command_mode == CMD_READ_STATUS || ff_command_mode == CMD_READ_STATUS_2 ) begin
				ff_wait_count	<= CS_WAIT_10NS;
			end
			else begin
				ff_wait_count	<= CS_WAIT_50NS;
			end
		end
		else if( ff_wait_count_active && ff_wait_count != 0 ) begin
			ff_wait_count	<= ff_wait_count - 1;
		end
	end

	always @( posedge clk ) begin
		if( reset ) begin
			ff_wait_count_active	<= 1'b0;
		end
		else if( ff_cs_n ) begin
			ff_wait_count_active	<= 1'b1;
		end
		else if( ff_wait_count_active ) begin
			//	ff_wait_count_active が 1 の場合は、ff_wait_count が 0 になるまで待つ。
			if( ff_wait_count == 0 ) begin
				ff_wait_count_active	<= 1'b0;
			end
		end
	end

	always @( posedge clk ) begin
		if( reset ) begin
			ff_finish_command		<= 1'b0;
		end
		else if( ff_serial_valid ) begin
		end
		else if( ff_finish_command && !ff_bus_ready && (!ff_cs_n || (ff_wait_count == 0)) ) begin
			ff_finish_command		<= 1'b0;
		end
		else begin
			if( ff_command_state == ST_FINISH ) begin
				if( w_serial_idle ) begin
					ff_finish_command		<= 1'b1;
				end
			end
		end
	end

	always @( posedge clk ) begin
		if( reset ) begin
			ff_cs_n					<= 1'b1;
			ff_command_state		<= ST_IDLE;
			ff_serial_mode			<= MODE_STD_WRITE;
			ff_serial_wdata			<= 8'd0;
			ff_serial_write			<= 1'b0;
			ff_serial_valid			<= 1'b0;
			ff_bus_rdata_en			<= 1'b0;
		end
		else if( ff_bus_rdata_en ) begin
			//	bus_rdata_en を 1clk だけアクティブにするための処理
			ff_bus_rdata_en	<= 1'b0;
		end
		else if( ff_serial_valid ) begin
			if( w_serial_ready ) begin
				case( ff_command_state )
					ST_READ_MODE: begin
						ff_command_state	<= ST_READ_ADDR_H;
						ff_serial_mode		<= MODE_STD_WRITE;
						ff_serial_wdata		<= ff_rom_address[23:16];
						ff_serial_write		<= 1'b1;
						ff_serial_valid		<= 1'b1;
					end
					ST_READ_ADDR_H: begin
						ff_command_state	<= ST_READ_ADDR_M;
						ff_serial_mode		<= MODE_STD_WRITE;
						ff_serial_wdata		<= ff_rom_address[15:8];
						ff_serial_write		<= 1'b1;
						ff_serial_valid		<= 1'b1;
					end
					ST_READ_ADDR_M: begin
						ff_command_state	<= ST_READ_ADDR_L;
						ff_serial_mode		<= MODE_STD_WRITE;
						ff_serial_wdata		<= ff_rom_address[7:0];
						ff_serial_write		<= 1'b1;
						ff_serial_valid		<= 1'b1;
					end
					ST_READ_ADDR_L: begin
						ff_command_state	<= ST_READ_DUMMY;
						ff_serial_mode		<= MODE_STD_WRITE;
						ff_serial_wdata		<= 8'h00;
						ff_serial_write		<= 1'b1;
						ff_serial_valid		<= 1'b1;
					end
					ST_READ_DUMMY: begin
						//	DUMMY(1byte) は ST_READ_ADDR_L で既に投入済み。
						//	ここで追加送信すると 2byte 分のダミークロックになってしまうため、
						//	次は READ 開始待ち状態へ遷移するだけにする。
						ff_command_state	<= ST_READ_BYTE;
						ff_serial_valid		<= 1'b0;
					end
					ST_BLOCK_ERASE_ADDR_H: begin
						ff_command_state	<= ST_BLOCK_ERASE_ADDR_M;
						ff_serial_mode		<= MODE_STD_WRITE;
						ff_serial_wdata		<= ff_rom_address[23:16];
						ff_serial_write		<= 1'b1;
						ff_serial_valid		<= 1'b1;
					end
					ST_BLOCK_ERASE_ADDR_M: begin
						ff_command_state	<= ST_BLOCK_ERASE_ADDR_L;
						ff_serial_mode		<= MODE_STD_WRITE;
						ff_serial_wdata		<= ff_rom_address[15:8];
						ff_serial_write		<= 1'b1;
						ff_serial_valid		<= 1'b1;
					end
					ST_BLOCK_ERASE_ADDR_L: begin
						ff_command_state	<= ST_FINISH;
						ff_serial_mode		<= MODE_STD_WRITE;
						ff_serial_wdata		<= ff_rom_address[7:0];
						ff_serial_write		<= 1'b1;
						ff_serial_valid		<= 1'b1;
					end
					default: begin
						ff_serial_valid	<= 1'b0;
					end
				endcase
			end
		end
		else begin
			case( ff_command_state )
				ST_IDLE: begin
					if( ff_do_command ) begin
						case( ff_command_mode )
							CMD_SINGLE_READ: begin
								//	このモードでは、data port からの読み出しのたびに
								//	Fast Read(0Bh) を発行する。
								ff_command_state		<= ST_READ_MODE;
								ff_serial_mode			<= MODE_STD_WRITE;
								ff_serial_wdata 		<= SROM_FAST_READ;
								ff_serial_write 		<= 1'b1;
								ff_serial_valid 		<= 1'b1;
								ff_cs_n					<= 1'b0;
							end
							CMD_BURST_READ: begin
								if( ff_cs_n ) begin
									//	burst read の初回は ff_cs_n = 1 なので、コマンド発行処理を実施。
									//	このモードでは、0x02 を書いた時点で 0Bh + address + dummy を発行し、
									//	その後の data port からの読み出しは、1byte 読み出しのみである。
									ff_command_state		<= ST_READ_MODE;
									ff_serial_mode			<= MODE_STD_WRITE;	//	通常の SPI モード
									ff_serial_wdata 		<= SROM_FAST_READ;
									ff_serial_write 		<= 1'b1;
									ff_serial_valid 		<= 1'b1;
									ff_cs_n					<= 1'b0;
								end
								else begin
									//	burst read の 2回目以降は、ff_cs_n = 0 のままデータを読み出す。
									ff_command_state		<= ST_RECEIVE_BYTE;
									ff_serial_mode			<= MODE_STD_READ;
									ff_serial_wdata 		<= 8'd0;
									ff_serial_write 		<= 1'b0;
									ff_serial_valid 		<= 1'b1;
								end
							end
							CMD_BURST_WRITE: begin
								if( ff_cs_n ) begin
									//	burst write の初回は ff_cs_n = 1 なので、コマンド発行処理を実施。
									//	このモードでは、0x03 を書いた時点でアドレスを発行し、その後の data port への書き込みは、1byte 書き込みのみである。
									ff_command_state		<= ST_WAIT;
									ff_next_command_state	<= ST_WRITE_MODE;
									ff_serial_mode			<= MODE_STD_WRITE;	//	通常の SPI モード
									ff_serial_wdata 		<= SROM_WRITE_ENABLE;
									ff_serial_write 		<= 1'b1;
									ff_serial_valid 		<= 1'b1;
									ff_cs_n					<= 1'b0;
								end
								else begin
									//	burst write の 2回目以降は、ff_cs_n = 0 なので、コマンド発行処理は不要。
									ff_command_state		<= ST_FINISH;
									ff_serial_mode			<= MODE_STD_WRITE;	//	通常の SPI モード
									ff_serial_wdata 		<= ff_burst_wdata;
									ff_serial_write 		<= 1'b1;
									ff_serial_valid 		<= 1'b1;
								end
							end
							CMD_CHIP_ERASE: begin
								//	Serial ROM 全体を消去するコマンドを発行する。
								ff_command_state		<= ST_WAIT;
								ff_next_command_state	<= ST_ERASE;
								ff_serial_mode			<= MODE_STD_WRITE;	//	通常の SPI モード
								ff_serial_wdata 		<= SROM_WRITE_ENABLE;
								ff_serial_write 		<= 1'b1;
								ff_serial_valid 		<= 1'b1;
								ff_cs_n					<= 1'b0;
							end
							CMD_READ_STATUS: begin
								if( ff_cs_n ) begin
									//	Serial ROM のステータスレジスタを読み出すモード。data port から、1byte 読み出すと、その最下位に busy ステータスが入る。
									ff_command_state		<= ST_READ_BYTE;
									ff_serial_mode			<= MODE_STD_WRITE;	//	通常の SPI モード
									ff_serial_wdata 		<= SROM_READ_STATUS_1;
									ff_serial_write 		<= 1'b1;
									ff_serial_valid 		<= 1'b1;
									ff_cs_n					<= 1'b0;
								end
								else begin
									ff_command_state		<= ST_RECEIVE_BYTE;
									ff_serial_mode			<= MODE_STD_READ;	//	通常の SPI モード
									ff_serial_wdata 		<= 8'd0;
									ff_serial_write 		<= 1'b0;
									ff_serial_valid 		<= 1'b1;
								end
							end
							CMD_READ_STATUS_2: begin
								if( ff_cs_n ) begin
									//	Serial ROM のステータスレジスタ2を読み出すモード。
									ff_command_state		<= ST_READ_BYTE;
									ff_serial_mode			<= MODE_STD_WRITE;	//	通常の SPI モード
									ff_serial_wdata 		<= SROM_READ_STATUS_2;
									ff_serial_write 		<= 1'b1;
									ff_serial_valid 		<= 1'b1;
									ff_cs_n					<= 1'b0;
								end
								else begin
									ff_command_state		<= ST_RECEIVE_BYTE;
									ff_serial_mode			<= MODE_STD_READ;	//	通常の SPI モード
									ff_serial_wdata 		<= 8'd0;
									ff_serial_write 		<= 1'b0;
									ff_serial_valid 		<= 1'b1;
								end
							end
							CMD_ACCESS_END: begin
								//	w_serial_idle が 1 になるのを待って、アクセスを終了する。
								ff_command_state	<= ST_FINISH;
							end
							CMD_WRITE_ENABLE: begin
								//	Issue only WRITE ENABLE (06h) and finish.
								ff_command_state		<= ST_WAIT;
								ff_next_command_state	<= ST_FINISH;
								ff_serial_mode			<= MODE_STD_WRITE;
								ff_serial_wdata 		<= SROM_WRITE_ENABLE;
								ff_serial_write 		<= 1'b1;
								ff_serial_valid 		<= 1'b1;
								ff_cs_n					<= 1'b0;
							end
							CMD_BLOCK_ERASE: begin
								//	Issue BLOCK_ERASE (D8h) + 24bit address.
								ff_command_state		<= ST_BLOCK_ERASE_ADDR_H;
								ff_serial_mode			<= MODE_STD_WRITE;
								ff_serial_wdata 		<= SROM_BLOCK_ERASE;
								ff_serial_write 		<= 1'b1;
								ff_serial_valid 		<= 1'b1;
								ff_cs_n					<= 1'b0;
							end
							default: begin
								//	reserved command, do nothing.
							end
						endcase
					end
				end
				ST_READ_MODE: begin
					ff_command_state	<= ST_READ_ADDR_H;
					ff_serial_mode		<= MODE_STD_WRITE;
					ff_serial_wdata		<= ff_rom_address[23:16];
					ff_serial_write		<= 1'b1;
					ff_serial_valid		<= 1'b1;
				end
				ST_READ_ADDR_H: begin
					ff_command_state	<= ST_READ_ADDR_M;
					ff_serial_mode		<= MODE_STD_WRITE;
					ff_serial_wdata		<= ff_rom_address[15:8];
					ff_serial_write		<= 1'b1;
					ff_serial_valid		<= 1'b1;
				end
				ST_READ_ADDR_M: begin
					ff_command_state	<= ST_READ_ADDR_L;
					ff_serial_mode		<= MODE_STD_WRITE;
					ff_serial_wdata		<= ff_rom_address[7:0];
					ff_serial_write		<= 1'b1;
					ff_serial_valid		<= 1'b1;
				end
				ST_READ_ADDR_L: begin
					ff_command_state	<= ST_READ_DUMMY;
					ff_serial_mode		<= MODE_STD_WRITE;
					ff_serial_wdata		<= 8'h00;
					ff_serial_write		<= 1'b1;
					ff_serial_valid		<= 1'b1;
				end
				ST_READ_DUMMY: begin
					ff_command_state	<= ST_READ_BYTE;
					ff_serial_mode		<= MODE_STD_WRITE;
					ff_serial_wdata		<= 8'd0;
					ff_serial_write		<= 1'b1;
					ff_serial_valid		<= 1'b1;
				end
				ST_READ_BYTE: begin
					if( w_serial_idle ) begin
						ff_command_state	<= ST_RECEIVE_BYTE;
						ff_serial_mode		<= MODE_STD_READ;
						ff_serial_wdata 	<= 8'd0;
						ff_serial_write 	<= 1'b0;
						ff_serial_valid 	<= 1'b1;
					end
				end
				ST_RECEIVE_BYTE: begin
					if( w_serial_rdata_en ) begin
						ff_bus_rdata		<= w_serial_rdata;
						ff_bus_rdata_en		<= 1'b1;
						ff_command_state	<= ST_FINISH;
					end
				end
				ST_WAIT: begin
					if( w_serial_idle ) begin
						ff_command_state		<= ff_next_command_state;
						ff_cs_n					<= 1'b1;
					end
				end
				ST_WRITE_MODE: begin
					if( ff_wait_count == 0 ) begin
						ff_command_state	<= ST_WRITE_ADDR_H;
						ff_serial_mode		<= MODE_STD_WRITE;	//	通常の SPI モード
						ff_serial_wdata 	<= SROM_PAGE_PROGRAM;
						ff_serial_write 	<= 1'b1;
						ff_serial_valid 	<= 1'b1;
						ff_cs_n				<= 1'b0;
					end
				end
				ST_WRITE_ADDR_H: begin
					ff_command_state	<= ST_WRITE_ADDR_M;
					ff_serial_mode		<= MODE_STD_WRITE;
					ff_serial_wdata		<= ff_rom_address[23:16];
					ff_serial_write		<= 1'b1;
					ff_serial_valid		<= 1'b1;
				end
				ST_WRITE_ADDR_M: begin
					ff_command_state	<= ST_WRITE_ADDR_L;
					ff_serial_mode		<= MODE_STD_WRITE;
					ff_serial_wdata		<= ff_rom_address[15:8];
					ff_serial_write		<= 1'b1;
					ff_serial_valid		<= 1'b1;
				end
				ST_WRITE_ADDR_L: begin
					ff_command_state	<= ST_WRITE_BYTE;
					ff_serial_mode		<= MODE_STD_WRITE;
					ff_serial_wdata		<= 8'h00;
					ff_serial_write		<= 1'b1;
					ff_serial_valid		<= 1'b1;
				end
				ST_WRITE_BYTE: begin
					ff_command_state	<= ST_FINISH;
					ff_serial_mode		<= MODE_STD_WRITE;	//	通常の SPI モード
					ff_serial_wdata 	<= ff_burst_wdata;
					ff_serial_write 	<= 1'b1;
					ff_serial_valid 	<= 1'b1;
				end
				ST_ERASE: begin
					if( ff_wait_count == 0 ) begin
						//	このモードでは、data port へのアクセスは行わない。
						ff_command_state	<= ST_FINISH;
						ff_serial_mode		<= MODE_STD_WRITE;	//	通常の SPI モード
						ff_serial_wdata 	<= SROM_CHIP_ERASE;
						ff_serial_write 	<= 1'b1;
						ff_serial_valid 	<= 1'b1;
						ff_cs_n				<= 1'b0;
					end
				end
				ST_FINISH: begin
					if( w_serial_idle ) begin
						ff_command_state	<= ST_IDLE;
						if( ff_command_mode == CMD_BURST_WRITE || ff_command_mode == CMD_BURST_READ || ff_command_mode == CMD_READ_STATUS || ff_command_mode == CMD_READ_STATUS_2 ) begin
							//	これらのコマンドは、data port からのアクセスが続くので、ff_cs_n はアクティブのままにする。
						end
						else begin
							//	それ以外のコマンドは、ff_cs_n を非アクティブにする。
							ff_cs_n					<= 1'b1;
						end
					end
				end
				default: begin
					//	不正なコマンドの場合は IDLE へ戻す
					ff_command_state	<= ST_IDLE;
				end
			endcase
		end
	end

	// ---------------------------------------------------------
	//	SPI communication request queue
	// ---------------------------------------------------------
	always @(posedge clk) begin
		if( reset ) begin
			ff_fifo_mode	<= 3'd0;
			ff_fifo_wdata	<= 8'd0;
			ff_fifo_write	<= 1'b0;
			ff_fifo_valid	<= 1'b0;
		end
		else if( !ff_fifo_valid ) begin
			if( ff_serial_valid ) begin
				ff_fifo_mode	<= ff_serial_mode;
				ff_fifo_wdata	<= ff_serial_wdata;
				ff_fifo_write	<= ff_serial_write;
				ff_fifo_valid	<= 1'b1;
			end
		end
		else begin
			if( !ff_xfer_valid && ff_xfer_ready ) begin
				ff_fifo_valid <= 1'b0;
			end
		end
	end

	always @(posedge clk) begin
		if( reset ) begin
			ff_xfer_mode	<= 3'd0;
			ff_xfer_wdata	<= 8'd0;
			ff_xfer_write	<= 1'b0;
			ff_xfer_valid	<= 1'b0;
		end
		else if( !ff_xfer_valid ) begin
			if( ff_fifo_valid && ff_xfer_ready ) begin
				ff_xfer_mode	<= ff_fifo_mode;
				ff_xfer_wdata	<= ff_fifo_wdata;
				ff_xfer_write	<= ff_fifo_write;
				ff_xfer_valid	<= 1'b1;
			end
		end
		else begin
			if( ff_xfer_spi_accepted ) begin
				ff_xfer_valid <= 1'b0;
			end
		end
	end

	always @( posedge clk ) begin
		if( reset ) begin
			ff_xfer_ready <= 1'b1;
		end
		else if( ff_xfer_ready ) begin
			if( ff_fifo_valid ) begin
				ff_xfer_ready <= 1'b0;
			end
		end
		else begin
			if( !ff_xfer_valid && !ff_xfer_spi_accepted ) begin
				ff_xfer_ready <= 1'b1;
			end
		end
	end

	always @(posedge clk) begin
		if( reset ) begin
			ff_xfer_processing		<= 1'b0;
			ff_xfer_spi_accepted	<= 1'b0;
		end
		else begin
			ff_xfer_processing		<= ff_spi_processing;
			ff_xfer_spi_accepted	<= ff_xfer_processing;
		end
	end

	always @( posedge clk ) begin
		if( reset ) begin
			ff_xfer_rdata		<= 8'd0;
			ff_xfer_rdata_en	<= 1'b0;
		end
		else if( !ff_xfer_processing && ff_xfer_spi_accepted ) begin
			ff_xfer_rdata		<= ff_spi_rdata;
			ff_xfer_rdata_en	<= ~ff_xfer_write;
		end
		else begin
			ff_xfer_rdata_en	<= 1'b0;
		end
	end

	assign w_serial_ready	= !ff_fifo_valid;
	assign w_serial_rdata	= ff_xfer_rdata;
	assign w_serial_rdata_en= ff_xfer_rdata_en;

	// ---------------------------------------------------------
	//	Request clock domain crossing
	// ---------------------------------------------------------
	always @( posedge clk_serial ) begin
		if( reset ) begin
			ff_spi_serial_valid0 <= 1'b0;
			ff_spi_serial_valid1 <= 1'b0;
		end
		else begin
			ff_spi_serial_valid0 <= ff_xfer_valid;
			ff_spi_serial_valid1 <= ff_spi_serial_valid0;
		end
	end

	always @( posedge clk_serial ) begin
		if( reset ) begin
			ff_spi_processing <= 1'b0;
		end
		else if( !ff_spi_processing ) begin
			if( ff_spi_serial_valid1 ) begin
				ff_spi_processing <= 1'b1;
			end
		end
		else begin
			if( ff_spi_state == ST_SPI_FINISH ) begin
				ff_spi_processing <= 1'b0;
			end
		end
	end

	//	Advance SPI transfer states every other clk_serial edge.
	//	This makes srom_clk frequency one quarter of clk_serial while keeping
	//	the existing high/low state sequencing unchanged.
	always @( posedge clk_serial ) begin
		if( reset ) begin
			ff_spi_ce <= 1'b0;
		end
		else if( ff_spi_processing ) begin
			ff_spi_ce <= ~ff_spi_ce;
		end
		else begin
			ff_spi_ce <= 1'b0;
		end
	end

	// ---------------------------------------------------------
	//	SPI transfer state machine
	// ---------------------------------------------------------
	always @( posedge clk_serial ) begin
		if( reset ) begin
			ff_spi_state		<= ST_SPI_IDLE;
			ff_spi_substate		<= 3'd0;
			ff_spi_clk			<= 1'b0;
			ff_spi_data			<= 8'd0;
			ff_spi_hiz			<= 4'b1111;
			ff_spi_sio			<= 4'b0000;
		end
		else if( ff_spi_processing ) begin
			if( ff_spi_ce ) begin
				case( ff_spi_state )
				ST_SPI_IDLE: begin
					case( ff_xfer_mode )
						MODE_STD_WRITE: begin
							ff_spi_state	<= ST_SPI_STD_WRITE;
							ff_spi_clk		<= 1'b0;
							ff_spi_data		<= ff_xfer_wdata;
							ff_spi_substate	<= 3'd7;
						end
						MODE_STD_READ: begin
							ff_spi_state	<= ST_SPI_STD_READ;
							ff_spi_clk		<= 1'b0;
							ff_spi_substate	<= 3'd7;
						end
						default: begin
							ff_spi_state	<= ST_SPI_FINISH;
							ff_spi_clk		<= 1'b0;
						end
					endcase
				end
				ST_SPI_STD_WRITE: begin
					ff_spi_clk		<= 1'b0;
					ff_spi_sio[0]	<= ff_spi_data[ff_spi_substate];
					ff_spi_sio[2]	<= 1'b1;
					ff_spi_sio[3]	<= 1'b1;
					ff_spi_hiz		<= 4'b0010;
					ff_spi_state	<= ST_SPI_STD_WRITE_CLK;
				end
				ST_SPI_STD_WRITE_CLK: begin
					ff_spi_clk		<= 1'b1;
					if( ff_spi_substate != 3'd0 ) begin
						ff_spi_substate	<= ff_spi_substate - 3'd1;
						ff_spi_state	<= ST_SPI_STD_WRITE;
					end
					else begin
						ff_spi_state	<= ST_SPI_FINISH;
					end
				end
				ST_SPI_STD_READ: begin
					ff_spi_clk		<= 1'b0;
					ff_spi_sio[2]	<= 1'b1;
					ff_spi_sio[3]	<= 1'b1;
					ff_spi_hiz		<= 4'b0011;
					ff_spi_state	<= ST_SPI_STD_READ_CLK;
				end
				ST_SPI_STD_READ_CLK: begin
					ff_spi_clk		<= 1'b1;
					ff_spi_state	<= ST_SPI_STD_READ_LOOP;
				end
				ST_SPI_STD_READ_LOOP: begin
					ff_spi_clk		<= 1'b0;
					ff_spi_data[ff_spi_substate] <= w_srom_sio[1];
					ff_spi_sio[2]	<= 1'b1;
					ff_spi_sio[3]	<= 1'b1;
					ff_spi_hiz		<= 4'b0011;
					if( ff_spi_substate != 3'd0 ) begin
						ff_spi_substate	<= ff_spi_substate - 3'd1;
						ff_spi_state	<= ST_SPI_STD_READ_CLK;
					end
					else begin
						ff_spi_state	<= ST_SPI_FINISH;
					end
				end
				ST_SPI_FINISH: begin
					ff_spi_clk		<= 1'b0;
					ff_spi_sio		<= 4'b0000;
					ff_spi_hiz		<= 4'b1111;
					ff_spi_state	<= ST_SPI_IDLE;
				end
				default: begin
				end
				endcase
			end
		end
		else begin
			ff_spi_state		<= ST_SPI_IDLE;
			ff_spi_substate		<= 3'd0;
			ff_spi_clk			<= 1'b0;
		end
	end

	always @( posedge clk_serial ) begin
		if( reset ) begin
			ff_spi_rdata	<= 8'd0;
		end
		else if( ff_spi_processing ) begin
			if( ff_spi_state == ST_SPI_FINISH ) begin
				ff_spi_rdata	<= ff_spi_data;
			end
		end
	end

	assign w_srom_sio[3]	= 1'b1;
	assign w_srom_sio[2]	= 1'b1;
	assign w_srom_sio[1]	= srom_do;
	assign w_srom_sio[0]	= srom_di;
	assign srom_clk			= ff_spi_clk;
	assign srom_di			= ff_spi_hiz[0] ? 1'bz : ff_spi_sio[0];
	assign srom_do			= 1'bz;
	assign srom_wp_n		= 1'b1;
	assign srom_hold_n		= 1'b1;
	assign w_serial_idle	= ff_xfer_ready & !ff_fifo_valid;

	assign srom0_cs_n = ff_srom0_cs_n | ff_wait_count_active;
	assign srom1_cs_n = ff_srom1_cs_n | ff_wait_count_active;
endmodule
