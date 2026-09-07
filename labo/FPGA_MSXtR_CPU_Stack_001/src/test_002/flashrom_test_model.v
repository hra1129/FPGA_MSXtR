// -----------------------------------------------------------------------------
// FlashROM test model for CPU boot simulation.
// The image is loaded as raw binary data with $fread.
// -----------------------------------------------------------------------------

module flashrom_test_model #(
	parameter IMAGE_FILE = ""
) (
	input						ce_n,
	input						oe_n,
	input		[18:0]		address,
	inout	[7:0]		data
);
	reg	[7:0]	rom_data [0:524287];
	integer		file_handle;
	integer		read_size;

	initial begin
		file_handle = $fopen( IMAGE_FILE, "rb" );
		if( file_handle == 0 ) begin
			$fatal( 1, "Cannot open FlashROM image: %s", IMAGE_FILE );
		end
		read_size = $fread( rom_data, file_handle );
		$fclose( file_handle );
		$display( "[FlashROM] loaded %s (%0d bytes)", IMAGE_FILE, read_size );
	end

	assign data = ( !ce_n && !oe_n ) ? rom_data[address] : 8'hZZ;
endmodule
