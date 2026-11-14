`timescale 1ns/1ps

module tb;
	reg clk = 1'b0;
	reg reset_n = 1'b0;
	reg [15:0] bus_address = 16'd0;
	reg device_io = 1'b0;
	reg device_write = 1'b0;
	reg [7:0] primary_slot = 8'h0C;
	reg [7:0] secondary_slot3 = 8'h08;
	reg bus_valid = 1'b0;
	reg [7:0] bus_wdata = 8'd0;
	wire dos_mapper_cs;
	wire kanji_rom_cs;
	wire performance_start_cs;
	wire performance_stop_cs;
	wire bus_ready;
	wire [7:0] bus_rdata;
	wire bus_rdata_en;
	wire decoder_ready;
	wire [7:0] decoder_rdata;
	wire decoder_rdata_en;
	wire [1:0] dos_bank;
	wire status_read;
	wire rdfdc_n;
	wire wrfdc_n;
	wire [3:0] fdc_address;
	wire fdc_interrupt;
	integer pass_count = 0;

	always #5 clk = ~clk;

	address_decode u_address_decode (
		.device_address		( bus_address ),
		.device_io			( device_io ),
		.device_write		( device_write ),
		.bootrom_en			( 1'b0 ),
		.primary_slot		( primary_slot ),
		.secondary_slot3	( secondary_slot3 ),
		.device_ppi_rdata		( 8'h00 ),
		.device_ppi_rdata_en	( 1'b0 ),
		.device_ppi_ready		( 1'b0 ),
		.device_mapper_rdata	( 8'h00 ),
		.device_mapper_rdata_en	( 1'b0 ),
		.device_mapper_ready	( 1'b0 ),
		.device_dos_mapper_rdata	( bus_rdata ),
		.device_dos_mapper_rdata_en	( bus_rdata_en ),
		.device_dos_mapper_ready	( bus_ready ),
		.device_secondary_rdata	( 8'h00 ),
		.device_secondary_rdata_en	( 1'b0 ),
		.device_secondary_ready	( 1'b0 ),
		.device_ssram_rdata		( 8'h00 ),
		.device_ssram_rdata_en	( 1'b0 ),
		.device_ssram_ready		( 1'b0 ),
		.device_rtc_rdata		( 8'h00 ),
		.device_rtc_rdata_en		( 1'b0 ),
		.device_rtc_ready		( 1'b0 ),
		.device_ssg_rdata		( 8'h00 ),
		.device_ssg_rdata_en		( 1'b0 ),
		.device_ssg_ready		( 1'b0 ),
		.device_kanji_rom_rdata	( 8'h00 ),
		.device_kanji_rom_rdata_en	( 1'b0 ),
		.device_kanji_rom_ready	( 1'b0 ),
		.device_system_flag_rdata	( 8'h00 ),
		.device_system_flag_rdata_en	( 1'b0 ),
		.device_system_flag_ready	( 1'b0 ),
		.device_pause_led_rdata	( 8'h00 ),
		.device_pause_led_rdata_en	( 1'b0 ),
		.device_pause_led_ready	( 1'b0 ),
		.device_bootrom_rdata		( 8'h00 ),
		.device_bootrom_rdata_en	( 1'b0 ),
		.device_bootrom_ready		( 1'b0 ),
		.device_s2026_rdata		( 8'h00 ),
		.device_s2026_rdata_en		( 1'b0 ),
		.device_s2026_ready		( 1'b0 ),
		.bootrom_cs			(),
		.ppi_cs				(),
		.memory_mapper_cs		(),
		.dos_mapper_cs			( dos_mapper_cs ),
		.performance_start_cs	( performance_start_cs ),
		.performance_stop_cs	( performance_stop_cs ),
		.ssram_cs			(),
		.rtc_cs				(),
		.ssg_cs				(),
		.kanji_rom_cs		( kanji_rom_cs ),
		.system_flag_cs		(),
		.pause_led_cs			(),
		.s2026_cs			(),
		.access_primary_slot		(),
		.access_secondary_slot3	(),
		.slot3_0_selected		(),
		.secondary_cs			(),
		.ssram_active			(),
		.device_rdata			( decoder_rdata ),
		.device_rdata_en		( decoder_rdata_en ),
		.device_ready			( decoder_ready )
	);

	dos_mapper u_dos_mapper (
		.reset_n			( reset_n ),
		.clk				( clk ),
		.bus_cs			( dos_mapper_cs ),
		.bus_address		( bus_address ),
		.bus_write		( device_write ),
		.bus_valid		( bus_valid ),
		.bus_wdata		( bus_wdata ),
		.bus_ready		( bus_ready ),
		.bus_rdata		( bus_rdata ),
		.bus_rdata_en		( bus_rdata_en ),
		.dos_bank			( dos_bank ),
		.status_read		( status_read ),
		.rdfdc_n			( rdfdc_n ),
		.wrfdc_n			( wrfdc_n ),
		.fdc_address		( fdc_address ),
		.fdc_interrupt		( fdc_interrupt )
	);

	task automatic check(input logic condition, input string message);
		if( !condition ) begin
			$fatal(1, "FAIL: %s", message);
		end
		pass_count = pass_count + 1;
		$display("PASS: %s", message);
	endtask

	task automatic set_bus(input [15:0] address, input logic write_access, input logic valid_access, input [7:0] data);
		bus_address = address;
		device_write = write_access;
		bus_valid = valid_access;
		bus_wdata = data;
		#1;
	endtask

	task automatic write_fdc_data(input [7:0] data_byte);
		set_bus(16'h7FF5, 1'b1, 1'b1, data_byte);
		@(posedge clk);
		#1;
	endtask

	task automatic check_msr(input [7:0] expected, input string message);
		set_bus(16'h7FF4, 1'b0, 1'b1, 8'h00);
		check(bus_rdata_en && decoder_rdata_en && bus_rdata == expected && decoder_rdata == expected, message);
	endtask

	task automatic read_fdc_result(input [7:0] expected, input string message);
		set_bus(16'h7FF5, 1'b0, 1'b1, 8'h00);
		check(bus_rdata_en && decoder_rdata_en && bus_rdata == expected && decoder_rdata == expected, message);
		@(posedge clk);
		#1;
	endtask

	initial begin
		repeat(2) @(posedge clk);
		#1 reset_n = 1'b1;
		check(dos_bank == 2'd0, "Reset initializes DOS bank to zero");
		set_bus(16'h7FF0, 1'b1, 1'b1, 8'hFD);
		check(dos_mapper_cs, "7FF0h write selected only for SLOT#3-2 page1");
		@(posedge clk);
		#1 check(dos_bank == 2'd1, "7FF0h stores only wdata[1:0]");
		set_bus(16'h7FF0, 1'b1, 1'b1, 8'hFE);
		@(posedge clk);
		#1 check(dos_bank == 2'd2, "7FF0h selects bank 2");
		set_bus(16'h7FF0, 1'b1, 1'b1, 8'hFF);
		@(posedge clk);
		#1 check(dos_bank == 2'd3, "7FF0h selects bank 3");
		set_bus(16'h7FF0, 1'b1, 1'b1, 8'hFC);
		@(posedge clk);
		#1 check(dos_bank == 2'd0, "7FF0h selects bank 0");

		set_bus(16'h7FF0, 1'b0, 1'b1, 8'h02);
		check(!dos_mapper_cs && dos_bank == 2'd0, "7FF0h read stays on ROM and does not change bank");

		set_bus(16'h7FF1, 1'b0, 1'b1, 8'h00);
		check(dos_mapper_cs && status_read, "7FF1h read selects the status register");
		check(bus_ready && decoder_ready && bus_rdata_en && decoder_rdata_en && bus_rdata == 8'hFF && decoder_rdata == 8'hFF, "Unimplemented status read completes with FFh");
		set_bus(16'h7FF1, 1'b1, 1'b1, 8'h00);
		check(dos_mapper_cs && !status_read && !bus_rdata_en, "7FF1h write is decoded without a read response");

		set_bus(16'h7FF2, 1'b0, 1'b1, 8'h00);
		check(dos_mapper_cs && !rdfdc_n && wrfdc_n && fdc_address == 4'h2, "7FF2h read asserts only /RDFDC");
		check_msr(8'h00, "FDC reset holds MSR inactive until FRES is released");
		set_bus(16'h7FF2, 1'b1, 1'b1, 8'h04);
		@(posedge clk);
		#1;
		set_bus(16'h7FF3, 1'b1, 1'b1, 8'h20);
		@(posedge clk);
		#1;
		check_msr(8'h80, "FRES release enables FDC command phase");
		write_fdc_data(8'h03);
		check_msr(8'h90, "SPECIFY command enters command phase");
		write_fdc_data(8'hDF);
		write_fdc_data(8'h01);
		check_msr(8'hA0, "SPECIFY completes and enables non-DMA status");

		write_fdc_data(8'h46);
		check_msr(8'hB0, "READ DATA command accepts its parameter packet");
		write_fdc_data(8'h00);
		write_fdc_data(8'h00);
		write_fdc_data(8'h00);
		write_fdc_data(8'h01);
		write_fdc_data(8'h02);
		write_fdc_data(8'h09);
		write_fdc_data(8'h1B);
		check_msr(8'hB0, "READ DATA remains in command phase until all nine bytes arrive");
		write_fdc_data(8'hFF);
		check_msr(8'hF0, "No-media READ DATA command enters result phase after byte nine");
		read_fdc_result(8'hC8, "READ DATA result reports not-ready abnormal termination");
		read_fdc_result(8'h04, "READ DATA result reports no data");
		read_fdc_result(8'h00, "READ DATA result ST2 has no additional error flags");
		read_fdc_result(8'h00, "READ DATA result returns cylinder");
		read_fdc_result(8'h00, "READ DATA result returns head");
		read_fdc_result(8'h01, "READ DATA result returns requested sector");
		read_fdc_result(8'h02, "READ DATA result returns requested size");
		check_msr(8'hA0, "Reading all seven result bytes returns to idle non-DMA mode");

		write_fdc_data(8'h0F);
		write_fdc_data(8'h00);
		write_fdc_data(8'h12);
		check(!fdc_interrupt, "F2h INTE=0 masks the SEEK interrupt output");
		write_fdc_data(8'h08);
		check_msr(8'hF0, "SENSE INTERRUPT STATUS enters result phase");
		read_fdc_result(8'h20, "SENSE INTERRUPT returns Seek End");
		read_fdc_result(8'h12, "SENSE INTERRUPT returns new cylinder");
		check_msr(8'hA0, "SENSE INTERRUPT clears IRQ and returns to idle non-DMA mode");
		check(!fdc_interrupt, "SENSE INTERRUPT clears IRQ request");
		set_bus(16'h7FF2, 1'b1, 1'b1, 8'h0C);
		@(posedge clk);
		write_fdc_data(8'h0F);
		write_fdc_data(8'h00);
		write_fdc_data(8'h20);
		check(fdc_interrupt, "F2h INTE=1 exposes the SEEK interrupt request");
		write_fdc_data(8'h08);
		read_fdc_result(8'h20, "Second SENSE INTERRUPT returns Seek End");
		read_fdc_result(8'h20, "Second SENSE INTERRUPT returns the new cylinder");
		check(!fdc_interrupt, "Second SENSE INTERRUPT acknowledges the IRQ");

		write_fdc_data(8'h01);
		check_msr(8'hF0, "Unsupported command returns an error result");
		read_fdc_result(8'h80, "Unsupported command reports invalid command");
		set_bus(16'h7FFB, 1'b1, 1'b1, 8'h00);
		check(dos_mapper_cs && rdfdc_n && !wrfdc_n && fdc_address == 4'hB, "7FFBh write asserts only /WRFDC");
		set_bus(16'h7FFC, 1'b0, 1'b1, 8'h00);
		check(!dos_mapper_cs && rdfdc_n && wrfdc_n, "7FFCh reserved address is not decoded");

		secondary_slot3[3:2] = 2'd1;
		set_bus(16'h7FF0, 1'b1, 1'b1, 8'h02);
		check(!dos_mapper_cs && dos_bank == 2'd0, "Other secondary slots cannot access the DOS mapper");
		device_io = 1'b1;
		secondary_slot3[3:2] = 2'd2;
		#1 check(!dos_mapper_cs, "I/O access does not select the memory-mapped DOS mapper");
		set_bus(16'h00F6, 1'b1, 1'b1, 8'h01);
		check(performance_start_cs && !performance_stop_cs && decoder_ready, "I/O write F6h starts measurement and completes immediately");
		set_bus(16'h00F7, 1'b1, 1'b1, 8'h00);
		check(!performance_start_cs && performance_stop_cs && decoder_ready, "I/O write F7h stops measurement and completes immediately");
		set_bus(16'h00F6, 1'b0, 1'b1, 8'h00);
		check(!performance_start_cs && !performance_stop_cs, "I/O reads do not trigger performance markers");
		set_bus(16'h00D7, 1'b0, 1'b1, 8'h00);
		check(!kanji_rom_cs, "D7h is outside Kanji ROM decode");
		set_bus(16'h00D8, 1'b0, 1'b1, 8'h00);
		check(kanji_rom_cs, "D8h selects Kanji ROM");
		set_bus(16'h00D9, 1'b1, 1'b1, 8'h00);
		check(kanji_rom_cs, "D9h address write selects Kanji ROM");
		set_bus(16'h00DA, 1'b0, 1'b1, 8'h00);
		check(kanji_rom_cs, "DAh selects Kanji ROM");
		set_bus(16'h00DB, 1'b1, 1'b1, 8'h00);
		check(kanji_rom_cs, "DBh address write selects Kanji ROM");
		set_bus(16'h00DC, 1'b0, 1'b1, 8'h00);
		check(!kanji_rom_cs, "DCh is outside Kanji ROM decode");

		$display("PASS: dos_mapper/performance marker checks=%0d", pass_count);
		$finish;
	end
endmodule