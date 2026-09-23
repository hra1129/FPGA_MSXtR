//
//	system_controller.v
//	 System Controller
//
//	Copyright (C) 2026 Takayuki Hara
//
//	本ソフトウェアおよび本ソフトウェアに基づいて作成された派生物は、以下の条件を
//	満たす場合に限り、再頒布および使用が許可されます。
//
//	1.ソースコード形式で再頒布する場合、上記の著作権表示、本条件一覧、および下記
//	  免責条項をそのままの形で保持すること。
//	2.バイナリ形式で再頒布する場合、頒布物に付属のドキュメント等の資料に、上記の
//	  著作権表示、本条件一覧、および下記免責条項を含めること。
//	3.書面による事前の許可なしに、本ソフトウェアを販売、および商業的な製品や活動
//	  に使用しないこと。
//
//	本ソフトウェアは、著作権者によって「現状のまま」提供されています。著作権者は、
//	特定目的への適合性の保証、商品性の保証、またそれに限定されない、いかなる明示
//	的もしくは暗黙な保証責任も負いません。著作権者は、事由のいかんを問わず、損害
//	発生の原因いかんを問わず、かつ責任の根拠が契約であるか厳格責任であるか（過失
//	その他の）不法行為であるかを問わず、仮にそのような損害が発生する可能性を知ら
//	されていたとしても、本ソフトウェアの使用によって発生した（代替品または代用サ
//	ービスの調達、使用の喪失、データの喪失、利益の喪失、業務の中断も含め、またそ
//	れに限定されない）直接損害、間接損害、偶発的な損害、特別損害、懲罰的損害、ま
//	たは結果損害について、一切責任を負わないものとします。
//
//	Note that above Japanese version license is the formal document.
//	The following translation is only for reference.
//
//	Redistribution and use of this software or any derivative works,
//	are permitted provided that the following conditions are met:
//
//	1. Redistributions of source code must retain the above copyright
//	   notice, this list of conditions and the following disclaimer.
//	2. Redistributions in binary form must reproduce the above
//	   copyright notice, this list of conditions and the following
//	   disclaimer in the documentation and/or other materials
//	   provided with the distribution.
//	3. Redistributions may not be sold, nor may they be used in a
//	   commercial product or activity without specific prior written
//	   permission.
//
//	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//	"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//	LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
//	FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
//	COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//	INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//	CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
//	LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
//	ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//	POSSIBILITY OF SUCH DAMAGE.
//
//-----------------------------------------------------------------------------

module system_controller#(
	parameter		device_id = 8'h61
) (
	input			clk,
	input			reset_n,
	input			bus_cs,
	input	[3:0]	bus_address,
	input			bus_valid,
	output			bus_ready,
	input			bus_write,
	input	[7:0]	bus_wdata,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	output			rom_bus_address,
	output			rom_bus_valid,
	input			rom_bus_ready,
	output			rom_bus_write,
	output	[7:0]	rom_bus_wdata,
	input	[7:0]	rom_bus_rdata,
	input			rom_bus_rdata_en,
	output			init_rom_bus_address,
	output			init_rom_bus_valid,
	input			init_rom_bus_ready,
	output			init_rom_bus_write,
	output	[7:0]	init_rom_bus_wdata,
	input	[7:0]	init_rom_bus_rdata,
	input			init_rom_bus_rdata_en,
	input			sram_ready,
	output			init_sram_bus_address,
	output			init_sram_bus_valid,
	input			init_sram_bus_ready,
	output			init_sram_bus_write,
	output	[7:0]	init_sram_bus_wdata,
	output			sram_initialize,
	output			wait_n
);
	localparam		c_io_enabler			= 4'h0;
	localparam		c_io_devsel				= 4'h1;
	localparam		c_io_address_l			= 4'h2;
	localparam		c_io_address_m			= 4'h3;
	localparam		c_io_address_h			= 4'h4;
	localparam		c_io_command			= 4'h5;
	localparam		c_io_data				= 4'h6;

	localparam		c_command_read			= 8'h00;
	localparam		c_command_write			= 8'h01;
	localparam		c_command_sector_erase	= 8'h02;
	localparam		c_command_all_erase		= 8'h03;

	localparam		c_st_init_sel_cmd		= 5'd0;
	localparam		c_st_init_sel_data		= 5'd1;
	localparam		c_st_idle				= 5'd2;
	localparam		c_st_addr_mode			= 5'd3;
	localparam		c_st_addr_l				= 5'd4;
	localparam		c_st_addr_m				= 5'd5;
	localparam		c_st_addr_h				= 5'd6;
	localparam		c_st_read_cmd			= 5'd7;
	localparam		c_st_read_req			= 5'd8;
	localparam		c_st_read_wait			= 5'd9;
	localparam		c_st_write_cmd			= 5'd10;
	localparam		c_st_write_data			= 5'd11;
	localparam		c_st_write_WAIT			= 5'd12;
	localparam		c_st_write_end			= 5'd13;
	localparam		c_st_write_end_wait		= 5'd14;
	localparam		c_st_erase_cmd			= 5'd15;
	localparam		c_st_erase_wait			= 5'd16;
	localparam		c_st_chip_cmd			= 5'd17;
	localparam		c_st_chip_data			= 5'd18;
	localparam		c_st_chip_wait			= 5'd19;
	localparam		c_st_init_wait_sram		= 5'd20;
	localparam		c_st_init_set_addr_cmd	= 5'd21;
	localparam		c_st_init_set_addr_l	= 5'd22;
	localparam		c_st_init_set_addr_m	= 5'd23;
	localparam		c_st_init_set_addr_h	= 5'd24;
	localparam		c_st_init_read_cmd		= 5'd25;
	localparam		c_st_init_read_req		= 5'd26;
	localparam		c_st_init_read_wait		= 5'd27;
	localparam		c_st_init_write_req		= 5'd28;
	localparam		c_st_init_write_wait		= 5'd29;
	localparam		c_st_init_done			= 5'd30;

	localparam	[22:0]	c_boot_rom_base		= 23'h7E0000;

	reg			ff_enable;
	reg			ff_devsel;
	reg	[22:0]	ff_address;
	reg	[7:0]	ff_data;
	reg	[7:0]	ff_rdata;
	reg			ff_rdata_en;
	reg	[4:0]	ff_state;
	reg	[1:0]	ff_rom_command;
	reg			ff_rom_bus_address;
	reg			ff_rom_bus_valid;
	reg			ff_rom_bus_write;
	reg		[4:0]	ff_init_state;
	reg		[18:0]	ff_init_src_count;
	reg		[18:0]	ff_init_dst_address;
	reg		[7:0]	ff_init_data;
	reg			ff_init_done;
	reg			ff_init_rom_bus_address;
	reg			ff_init_rom_bus_valid;
	reg			ff_init_rom_bus_write;
	reg	[7:0]	ff_init_rom_bus_wdata;
	reg			ff_init_sram_bus_address;
	reg			ff_init_sram_bus_valid;
	reg			ff_init_sram_bus_write;
	reg	[7:0]	ff_init_sram_bus_wdata;
	reg	[7:0]	ff_rom_bus_wdata;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_enable <= 1'b0;
		end
		else if( bus_cs && bus_valid && bus_write && bus_address == c_io_enabler ) begin
			ff_enable <= (bus_wdata == 8'h40);
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_devsel <= 1'b0;
		end
		else if( !ff_enable ) begin
			ff_devsel <= 1'b0;
		end
		else if( bus_cs && bus_valid && bus_write && bus_address == c_io_devsel ) begin
			ff_devsel <= (bus_wdata == device_id);
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_address <= 23'd0;
		end
		else if( ff_enable && ff_devsel && bus_cs && bus_valid && bus_write ) begin
			case( bus_address )
			c_io_address_l:		ff_address[ 7: 0] <= bus_wdata;
			c_io_address_m:		ff_address[15: 8] <= bus_wdata;
			c_io_address_h:		ff_address[22:16] <= bus_wdata[6:0];
			default:				;
			endcase
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_data <= 8'd0;
		end
		else if( rom_bus_rdata_en && ff_state == c_st_read_wait ) begin
			ff_data <= rom_bus_rdata;
		end
		else if( ff_enable && ff_devsel && bus_cs && bus_valid && bus_write && bus_address == c_io_data ) begin
			ff_data <= bus_wdata;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_state <= c_st_idle;
			ff_rom_command <= 2'd0;
			ff_rom_bus_address <= 1'b0;
			ff_rom_bus_valid <= 1'b0;
			ff_rom_bus_write <= 1'b0;
			ff_rom_bus_wdata <= 8'd0;
		end
		else begin
			ff_rom_bus_valid <= 1'b0;
			case( ff_state )
			c_st_idle: begin
				if( ff_enable && ff_devsel && bus_cs && bus_valid && bus_write && bus_address == c_io_command ) begin
					case( bus_wdata )
					c_command_read: begin
						ff_rom_command <= 2'd0;
						ff_state <= c_st_addr_mode;
					end
					c_command_write: begin
						ff_rom_command <= 2'd1;
						ff_state <= c_st_addr_mode;
					end
					c_command_sector_erase: begin
						ff_rom_command <= 2'd2;
						ff_state <= c_st_addr_mode;
					end
					c_command_all_erase: begin
						ff_rom_command <= 2'd3;
						ff_state <= c_st_chip_cmd;
					end
					default: ;
					endcase
				end
			end
			c_st_addr_mode: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b0;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= 8'h00;
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_addr_l;
				end
			end
			c_st_addr_l: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b1;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= ff_address[7:0];
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_addr_m;
				end
			end
			c_st_addr_m: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b1;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= ff_address[15:8];
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_addr_h;
				end
			end
			c_st_addr_h: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b1;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= { 1'b0, ff_address[22:16] };
					ff_rom_bus_valid <= 1'b1;
					case( ff_rom_command )
					2'd0:	ff_state <= c_st_read_cmd;
					2'd1:	ff_state <= c_st_write_cmd;
					default:	ff_state <= c_st_erase_cmd;
					endcase
				end
			end
			c_st_read_cmd: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b0;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= 8'h01;
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_read_req;
				end
			end
			c_st_read_req: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b1;
					ff_rom_bus_write <= 1'b0;
					ff_rom_bus_wdata <= 8'd0;
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_read_wait;
				end
			end
			c_st_read_wait: begin
				if( rom_bus_rdata_en ) begin
					ff_state <= c_st_idle;
				end
			end
			c_st_write_cmd: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b0;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= 8'h03;
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_write_data;
				end
			end
			c_st_write_data: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b1;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= ff_data;
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_write_WAIT;
				end
			end
			c_st_write_WAIT: begin
				if( rom_bus_ready ) begin
					ff_state <= c_st_write_end;
				end
			end
			c_st_write_end: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b0;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= 8'h07;
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_write_end_wait;
				end
			end
			c_st_write_end_wait: begin
				if( rom_bus_ready ) begin
					ff_state <= c_st_idle;
				end
			end
			c_st_erase_cmd: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b0;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= 8'h09;
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_erase_wait;
				end
			end
			c_st_erase_wait: begin
				if( rom_bus_ready ) begin
					ff_state <= c_st_idle;
				end
			end
			c_st_chip_cmd: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b0;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= 8'h04;
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_chip_data;
				end
			end
			c_st_chip_data: begin
				if( rom_bus_ready ) begin
					ff_rom_bus_address <= 1'b1;
					ff_rom_bus_write <= 1'b1;
					ff_rom_bus_wdata <= 8'h00;
					ff_rom_bus_valid <= 1'b1;
					ff_state <= c_st_chip_wait;
				end
			end
			c_st_chip_wait: begin
				if( rom_bus_ready ) begin
					ff_state <= c_st_idle;
				end
			end
			default: begin
				ff_state <= c_st_idle;
			end
			endcase
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rdata <= 8'hFF;
		end
		else if( bus_cs && !bus_write ) begin
			case( bus_address )
			c_io_enabler:	ff_rdata <= ff_enable ? 8'hBF : 8'hFF;
			c_io_devsel:	ff_rdata <= (ff_enable && ff_devsel) ? ~device_id[7:0] : 8'hFF;
			c_io_address_l:	ff_rdata <= (ff_enable && ff_devsel) ? ff_address[ 7: 0] : 8'hFF;
			c_io_address_m:	ff_rdata <= (ff_enable && ff_devsel) ? ff_address[15: 8] : 8'hFF;
			c_io_address_h:	ff_rdata <= (ff_enable && ff_devsel) ? { 1'b0, ff_address[22:16] } : 8'hFF;
			c_io_command:	ff_rdata <= 8'hFF;
			c_io_data:		ff_rdata <= (ff_enable && ff_devsel) ? ff_data : 8'hFF;
			default:		ff_rdata <= 8'hFF;
			endcase
		end
		else begin
			ff_rdata <= 8'hFF;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rdata_en <= 1'b0;
		end
		else if( bus_cs && !bus_write && ff_state == c_st_idle ) begin
			ff_rdata_en <= 1'b1;
		end
		else begin
			ff_rdata_en <= 1'b0;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_init_state <= c_st_init_wait_sram;
			ff_init_src_count <= 19'd0;
			ff_init_dst_address <= 19'd0;
			ff_init_data <= 8'd0;
			ff_init_done <= 1'b0;
			ff_init_rom_bus_address <= 1'b0;
			ff_init_rom_bus_valid <= 1'b0;
			ff_init_rom_bus_write <= 1'b0;
			ff_init_rom_bus_wdata <= 8'd0;
			ff_init_sram_bus_address <= 1'b0;
			ff_init_sram_bus_valid <= 1'b0;
			ff_init_sram_bus_write <= 1'b0;
			ff_init_sram_bus_wdata <= 8'd0;
		end
		else begin
			ff_init_rom_bus_valid <= 1'b0;
			ff_init_sram_bus_valid <= 1'b0;
			case( ff_init_state )
			c_st_init_wait_sram: begin
				if( sram_ready ) begin
					ff_init_dst_address <= 19'd0;
					ff_init_state <= c_st_init_sel_cmd;
				end
			end
			c_st_init_sel_cmd: begin
				if( init_rom_bus_ready ) begin
					ff_init_rom_bus_address <= 1'b0;
					ff_init_rom_bus_write <= 1'b1;
					ff_init_rom_bus_wdata <= 8'h06;
					ff_init_rom_bus_valid <= 1'b1;
					ff_init_state <= c_st_init_sel_data;
				end
			end
			c_st_init_sel_data: begin
				if( init_rom_bus_ready ) begin
					ff_init_rom_bus_address <= 1'b1;
					ff_init_rom_bus_write <= 1'b1;
					ff_init_rom_bus_wdata <= 8'h00;
					ff_init_rom_bus_valid <= 1'b1;
					ff_init_state <= c_st_init_set_addr_cmd;
				end
			end
			c_st_init_set_addr_cmd: begin
				if( init_rom_bus_ready ) begin
					ff_init_rom_bus_address <= 1'b0;
					ff_init_rom_bus_write <= 1'b1;
					ff_init_rom_bus_wdata <= 8'h00;
					ff_init_rom_bus_valid <= 1'b1;
					ff_init_state <= c_st_init_set_addr_l;
				end
			end
			c_st_init_set_addr_l: begin
				if( init_rom_bus_ready ) begin
					ff_init_rom_bus_address <= 1'b1;
					ff_init_rom_bus_write <= 1'b1;
					ff_init_rom_bus_wdata <= 8'h00;
					ff_init_rom_bus_valid <= 1'b1;
					ff_init_state <= c_st_init_set_addr_m;
				end
			end
			c_st_init_set_addr_m: begin
				if( init_rom_bus_ready ) begin
					ff_init_rom_bus_address <= 1'b1;
					ff_init_rom_bus_write <= 1'b1;
					ff_init_rom_bus_wdata <= 8'h00;
					ff_init_rom_bus_valid <= 1'b1;
					ff_init_state <= c_st_init_set_addr_h;
				end
			end
			c_st_init_set_addr_h: begin
				if( init_rom_bus_ready ) begin
					ff_init_rom_bus_address <= 1'b1;
					ff_init_rom_bus_write <= 1'b1;
					ff_init_rom_bus_wdata <= 8'h78;
					ff_init_rom_bus_valid <= 1'b1;
					ff_init_state <= c_st_init_read_cmd;
				end
			end
			c_st_init_read_cmd: begin
				if( init_rom_bus_ready ) begin
					ff_init_rom_bus_address <= 1'b0;
					ff_init_rom_bus_write <= 1'b1;
					ff_init_rom_bus_wdata <= 8'h01;
					ff_init_rom_bus_valid <= 1'b1;
					ff_init_state <= c_st_init_read_req;
				end
			end
			c_st_init_read_req: begin
				if( init_rom_bus_ready ) begin
					ff_init_rom_bus_address <= 1'b1;
					ff_init_rom_bus_write <= 1'b0;
					ff_init_rom_bus_wdata <= 8'd0;
					ff_init_rom_bus_valid <= 1'b1;
					ff_init_state <= c_st_init_read_wait;
				end
			end
			c_st_init_read_wait: begin
				if( init_rom_bus_rdata_en ) begin
					ff_init_data <= init_rom_bus_rdata;
					ff_init_state <= c_st_init_write_req;
				end
			end
			c_st_init_write_req: begin
				if( init_sram_bus_ready ) begin
					ff_init_sram_bus_address <= ff_init_dst_address;
					ff_init_sram_bus_write <= 1'b1;
					ff_init_sram_bus_wdata <= ff_init_data;
					ff_init_sram_bus_valid <= 1'b1;
					ff_init_state <= c_st_init_write_wait;
				end
			end
			c_st_init_write_wait: begin
				if( init_sram_bus_ready ) begin
					if( ff_init_dst_address == 19'h7FFFF ) begin
						ff_init_state <= c_st_init_done;
					end
					else begin
						ff_init_dst_address <= ff_init_dst_address + 19'd1;
						ff_init_state <= c_st_init_read_req;
					end
				end
			end
			c_st_init_done: begin
				ff_init_done <= 1'b1;
			end
			default: begin
				ff_init_state <= c_st_init_wait_sram;
			end
			endcase
		end
	end

	assign bus_ready = (ff_state == c_st_idle);
	assign bus_rdata = ff_rdata;
	assign bus_rdata_en = ff_rdata_en;

	assign rom_bus_address = ff_rom_bus_address;
	assign rom_bus_valid = ff_rom_bus_valid;
	assign rom_bus_write = ff_rom_bus_write;
	assign rom_bus_wdata = ff_rom_bus_wdata;

	assign init_rom_bus_address = ff_init_rom_bus_address;
	assign init_rom_bus_valid = ff_init_rom_bus_valid;
	assign init_rom_bus_write = ff_init_rom_bus_write;
	assign init_rom_bus_wdata = ff_init_rom_bus_wdata;
	assign init_sram_bus_address = ff_init_sram_bus_address;
	assign init_sram_bus_valid = ff_init_sram_bus_valid;
	assign init_sram_bus_write = ff_init_sram_bus_write;
	assign init_sram_bus_wdata = ff_init_sram_bus_wdata;

	assign sram_initialize = ~ff_init_done;
	assign wait_n = ff_init_done;

endmodule
