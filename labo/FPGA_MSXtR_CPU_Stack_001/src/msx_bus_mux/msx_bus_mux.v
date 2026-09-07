// -----------------------------------------------------------------------------
//	msx_bus_mux.v
//	  MSX internal bus owner selector
// -----------------------------------------------------------------------------

module msx_bus_mux (
	input			reset_n,
	input			clk,
	input			bus_owner,
	output			active_bus_owner,
	//	Pico SPI side
	input			pico_bus_m1,
	input	[15:0]	pico_bus_address,
	input			pico_bus_io,
	input			pico_bus_write,
	input			pico_bus_valid,
	output			pico_bus_ready,
	input	[7:0]	pico_bus_wdata,
	output	[7:0]	pico_bus_rdata,
	output			pico_bus_rdata_en,
	input	[19:0]	pico_flashrom_address,
	input			pico_flashrom_en,
	//	CPU side
	input			cpu_bus_m1,
	input	[15:0]	cpu_bus_address,
	input			cpu_bus_io,
	input			cpu_bus_write,
	input			cpu_bus_valid,
	output			cpu_bus_ready,
	input	[7:0]	cpu_bus_wdata,
	output	[7:0]	cpu_bus_rdata,
	output			cpu_bus_rdata_en,
	//	msx_slot side
	output			msx_bus_m1,
	output	[15:0]	msx_bus_address,
	output			msx_bus_io,
	output			msx_bus_write,
	output			msx_bus_valid,
	input			msx_bus_ready,
	output	[7:0]	msx_bus_wdata,
	input	[7:0]	msx_bus_rdata,
	input			msx_bus_rdata_en,
	output	[19:0]	msx_flashrom_address,
	output			msx_flashrom_en
);
	reg				ff_active_bus_owner;
	wire			w_bus_idle;

	assign w_bus_idle = !pico_bus_valid && !cpu_bus_valid;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_active_bus_owner <= 1'b0;
		end
		else if( w_bus_idle ) begin
			ff_active_bus_owner <= bus_owner;
		end
	end

	assign active_bus_owner		= ff_active_bus_owner;
	assign msx_bus_m1			= ff_active_bus_owner ? cpu_bus_m1      : pico_bus_m1;
	assign msx_bus_address		= ff_active_bus_owner ? cpu_bus_address : pico_bus_address;
	assign msx_bus_io			= ff_active_bus_owner ? cpu_bus_io      : pico_bus_io;
	assign msx_bus_write		= ff_active_bus_owner ? cpu_bus_write   : pico_bus_write;
	assign msx_bus_valid		= ff_active_bus_owner ? cpu_bus_valid   : pico_bus_valid;
	assign msx_bus_wdata		= ff_active_bus_owner ? cpu_bus_wdata   : pico_bus_wdata;
	assign msx_flashrom_address	= ff_active_bus_owner ? 20'd0           : pico_flashrom_address;
	assign msx_flashrom_en		= ff_active_bus_owner ? 1'b0            : pico_flashrom_en;

	assign pico_bus_ready		= ff_active_bus_owner ? 1'b0 : msx_bus_ready;
	assign pico_bus_rdata		= msx_bus_rdata;
	assign pico_bus_rdata_en	= ff_active_bus_owner ? 1'b0 : msx_bus_rdata_en;

	assign cpu_bus_ready		= ff_active_bus_owner ? msx_bus_ready : 1'b0;
	assign cpu_bus_rdata		= msx_bus_rdata;
	assign cpu_bus_rdata_en		= ff_active_bus_owner ? msx_bus_rdata_en : 1'b0;
endmodule