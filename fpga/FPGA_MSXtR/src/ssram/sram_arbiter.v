// --------------------------------------------------------------------
//	SRAM Arbiter
// ====================================================================
//	2026/03/01 t.hara
// --------------------------------------------------------------------

module sram_arbiter (
	input			clk,
	input			reset_n,
	//	SRAM interface for CPU side
	input	[17:0]	cpu_address,
	input			cpu_valid,
	output			cpu_ready,
	input			cpu_write,
	input	[7:0]	cpu_wdata,
	output	[7:0]	cpu_rdata,
	output			cpu_rdata_en,
	//	SRAM interface for ADPCM side
	input	[17:0]	adpcm_address,
	input			adpcm_valid,
	output			adpcm_ready,
	input			adpcm_write,
	input	[7:0]	adpcm_wdata,
	output	[7:0]	adpcm_rdata,
	output			adpcm_rdata_en,
	//	SRAM interface for SerialSRAM
	output	[18:0]	ssram_address,
	output			ssram_valid,
	input			ssram_ready,
	output			ssram_write,
	output	[7:0]	ssram_wdata,
	input	[7:0]	ssram_rdata,
	input			ssram_rdata_en
);
	reg		[2:0]	ff_divider;
	wire			w_active;
	reg				ff_adpcm_phase;

	// ---------------------------------------------------------
	//	Active timing generator
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_divider <= 3'd0;
		end
		else begin
			ff_divider <= ff_divider + 3'd1;
		end
	end
	assign w_active	= ( ff_divider == 3'd7 );

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_adpcm_phase <= 1'b0;
		end
		else if( w_active ) begin
			if( !cpu_valid && adpcm_valid ) begin
				ff_adpcm_phase <= 1'b1;
			end
			else begin
				ff_adpcm_phase <= 1'b0;
			end
		end
	end

	// ---------------------------------------------------------
	//	Arbitration
	// ---------------------------------------------------------
	assign ssram_address	= cpu_valid ? { 1'b0, cpu_address } : { 1'b1, adpcm_address };
	assign ssram_write		= cpu_valid ? cpu_write : adpcm_write;
	assign ssram_wdata		= cpu_valid ? cpu_wdata : adpcm_wdata;
	assign ssram_valid		= w_active & (cpu_valid | adpcm_valid);

	assign cpu_ready		= w_active & ssram_ready;
	assign adpcm_ready		= w_active & ssram_ready & !cpu_valid;

	assign cpu_rdata		= ssram_rdata;
	assign cpu_rdata_en		= ssram_rdata_en & !ff_adpcm_phase;
	assign adpcm_rdata		= ssram_rdata;
	assign adpcm_rdata_en	= ssram_rdata_en & ff_adpcm_phase;
endmodule
