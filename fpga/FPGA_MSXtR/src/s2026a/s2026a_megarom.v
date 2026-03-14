//
// s2026a_megarom.v
//   System MegaROM
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

module s2026a_megarom (
	input			reset_n,
	input			clk85m,
	input			bus_cs,
	input			bus_write,
	input			bus_valid,
	output			bus_ready,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	input	[7:0]	bus_wdata,
	input	[15:0]	bus_address,
	//	SDRAM I/F
	output	[22:0]	sdram_address,
	output			sdram_valid,
	input			sdram_ready,
	output			sdram_write,
	output	[7:0]	sdram_wdata
);
	reg		[8:0]	ff_bank0;
	reg		[8:0]	ff_bank1;
	reg		[8:0]	ff_bank2;
	reg		[8:0]	ff_bank3;
	reg		[8:0]	ff_bank4;
	reg		[8:0]	ff_bank5;
	reg		[8:0]	ff_bank6;
	reg		[8:0]	ff_bank7;
	wire	[8:0]	w_bank;
	reg				ff_megarom_ee;		// Extended Bank Register Read/Write Enable
	reg				ff_megarom_ce;		// Control Register Read Enable
	reg				ff_megarom_be;		// Bank Register Read Enable
	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;
	reg		[22:0]	ff_sdram_address;
	reg				ff_sdram_valid;
	reg				ff_sdram_write;
	reg		[7:0]	ff_sdram_wdata;

	// ---------------------------------------------------------
	//	Wait / Ready
	// ---------------------------------------------------------
	assign bus_ready	= ~ff_sdram_valid & ~ff_rdata_en;

	//--------------------------------------------------------------
	//	MegaROM Mapper
	//		7FF0h: BANK0[7:0] ※BE=1 の時のみ Read可
	//		7FF1h: BANK1[7:0] ※BE=1 の時のみ Read可
	//		7FF2h: BANK2[7:0] ※BE=1 の時のみ Read可
	//		7FF3h: BANK3[7:0] ※BE=1 の時のみ Read可
	//		7FF4h: BANK4[7:0] ※BE=1 の時のみ Read可
	//		7FF5h: BANK5[7:0] ※BE=1 の時のみ Read可
	//		7FF6h: BANK6[7:0] ※BE=1 の時のみ Read可
	//		7FF7h: BANK7[7:0] ※BE=1 の時のみ Read可
	//		7FF8h: BANK0～7[8] ※EE=1 の時のみ Read可
	//		7FF9h: Control Register EE[4], CE[3], BE[2] ※CE=1 の時のみ Read可
	//--------------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_megarom_ee <= 1'b0;
			ff_megarom_ce <= 1'b0;
			ff_megarom_be <= 1'b0;
			ff_bank0 <= 9'd0;
			ff_bank1 <= 9'd0;
			ff_bank2 <= 9'd0;
			ff_bank3 <= 9'd0;
			ff_bank4 <= 9'd0;
			ff_bank5 <= 9'd0;
			ff_bank6 <= 9'd0;
			ff_bank7 <= 9'd0;
			ff_rdata <= 8'd0;
			ff_rdata_en <= 1'b0;
			ff_sdram_valid <= 1'b0;
			ff_sdram_write <= 1'b0;
		end
		else if( ff_sdram_valid ) begin
			if( sdram_ready ) begin
				ff_sdram_valid <= 1'b0;
			end
		end
		else if( ff_rdata_en ) begin
			ff_rdata_en <= 1'b0;
		end
		else if( bus_cs && bus_valid ) begin
			if( bus_write ) begin
				//	Write
				if( bus_address[15:4] == 12'h7FF ) begin
					case( bus_address[3:0] )
						4'd8: begin
							if( ff_megarom_ee ) begin
								ff_bank0[8] <= bus_wdata[0];
								ff_bank1[8] <= bus_wdata[1];
								ff_bank2[8] <= bus_wdata[2];
								ff_bank3[8] <= bus_wdata[3];
								ff_bank4[8] <= bus_wdata[4];
								ff_bank5[8] <= bus_wdata[5];
								ff_bank6[8] <= bus_wdata[6];
								ff_bank7[8] <= bus_wdata[7];
							end
						end
						4'd9: begin
							ff_megarom_ee <= bus_wdata[4];
							ff_megarom_ce <= bus_wdata[3];
							ff_megarom_be <= bus_wdata[2];
						end
						default: begin
							//	no effect
						end
					endcase
				end
				else if( bus_address[15:13] == 3'b011 ) begin
					case( bus_address[12:10] )
						3'd0:		ff_bank0[7:0] <= bus_wdata;
						3'd1:		ff_bank1[7:0] <= bus_wdata;
						3'd2:		ff_bank2[7:0] <= bus_wdata;
						3'd3:		ff_bank3[7:0] <= bus_wdata;
						3'd4:		ff_bank4[7:0] <= bus_wdata;
						3'd5:		ff_bank5[7:0] <= bus_wdata;
						3'd6:		ff_bank6[7:0] <= bus_wdata;
						3'd7:		ff_bank7[7:0] <= bus_wdata;
						default:	ff_bank0[7:0] <= bus_wdata;
					endcase
				end
				else if( w_bank[8:7] == 2'b11 ) begin
					//	write SDRAM (MapperRAM Bank)
					ff_sdram_address	<= { 1'b0, w_bank, bus_address[12:0] };
					ff_sdram_valid		<= 1'b1;
					ff_sdram_write		<= 1'b1;
					ff_sdram_wdata		<= bus_wdata;
				end
			end
			else begin
				//	Read
				if(      ff_megarom_be && (bus_address[15:3] == 13'b0111_1111_1111_0) ) begin
					ff_rdata_en <= 1'b1;
					case( bus_address[2:0] )
						3'd0:		ff_rdata <= ff_bank0[7:0];
						3'd1:		ff_rdata <= ff_bank1[7:0];
						3'd2:		ff_rdata <= ff_bank2[7:0];
						3'd3:		ff_rdata <= ff_bank3[7:0];
						3'd4:		ff_rdata <= ff_bank4[7:0];
						3'd5:		ff_rdata <= ff_bank5[7:0];
						3'd6:		ff_rdata <= ff_bank6[7:0];
						3'd7:		ff_rdata <= ff_bank7[7:0];
						default:	ff_rdata <= ff_bank0[7:0];
					endcase
				end
				else if( ff_megarom_ee && (bus_address == 16'h7FF8) ) begin
					ff_rdata_en <= 1'b1;
					ff_rdata <= {ff_bank7[8], ff_bank6[8], ff_bank5[8], ff_bank4[8], ff_bank3[8], ff_bank2[8], ff_bank1[8], ff_bank0[8]};
				end
				else if( ff_megarom_ce && (bus_address == 16'h7FF9) ) begin
					ff_rdata_en <= 1'b1;
					ff_rdata <= { 3'b000, ff_megarom_ee, ff_megarom_ce, ff_megarom_be, 2'b00 };
				end
				else begin
					//	read SDRAM
					ff_sdram_address	<= { 1'b0, w_bank, bus_address[12:0] };
					ff_sdram_valid		<= 1'b1;
					ff_sdram_write		<= 1'b0;
				end
			end
		end
	end

	assign w_bank	= (bus_address[15:13] == 3'd0) ? ff_bank0: 
	                  (bus_address[15:13] == 3'd1) ? ff_bank1: 
	                  (bus_address[15:13] == 3'd2) ? ff_bank2: 
	                  (bus_address[15:13] == 3'd3) ? ff_bank3: 
	                  (bus_address[15:13] == 3'd4) ? ff_bank4: 
	                  (bus_address[15:13] == 3'd5) ? ff_bank5: 
	                  (bus_address[15:13] == 3'd6) ? ff_bank6: ff_bank7;

	assign bus_rdata			= ff_rdata;
	assign bus_rdata_en		= ff_rdata_en;

	assign sdram_address	= ff_sdram_address;
	assign sdram_valid		= ff_sdram_valid;
	assign sdram_write		= ff_sdram_write;
	assign sdram_wdata		= ff_sdram_wdata;
endmodule
