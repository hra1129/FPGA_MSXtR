// -----------------------------------------------------------------------------
//	Test of memory_mapper_inst.v
//	Copyright (C)2026 Takayuki Hara (HRA!)
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
// --------------------------------------------------------------------

module tb ();
	localparam		clk_base	= 1_000_000_000_000.0/42_954_540.0;	//	ps
	reg				reset_n;
	reg				clk;
	reg				bus_cs;
	reg				bus_write;
	reg				bus_valid;
	wire			bus_ready;
	reg		[15:0]	bus_address;
	reg		[7:0]	bus_wdata;
	wire	[7:0]	mapper_segment;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	memory_mapper_inst u_memory_mapper_inst(
		.reset_n			( reset_n			),
		.clk				( clk				),
		.bus_cs				( bus_cs			),
		.bus_write			( bus_write			),
		.bus_valid			( bus_valid			),
		.bus_ready			( bus_ready			),
		.bus_address		( bus_address		),
		.bus_wdata			( bus_wdata			),
		.mapper_segment		( mapper_segment	)
	);

	// --------------------------------------------------------------------
	//	clock
	// --------------------------------------------------------------------
	always #(clk_base/2) begin
		clk <= ~clk;
	end

	// --------------------------------------------------------------------
	//	Tasks
	// --------------------------------------------------------------------
	task reg_write(
		input	[15:0]	p_address,
		input	[7:0]	p_data
	);
		int count;

		count		<= 0;
		bus_cs		<= (p_address[7:2] == 6'h3F) ? 1'b1 : 1'b0;	//	only port 0xFC-0xFF is writable
		bus_write	<= 1'b1;
		bus_valid	<= 1'b1;
		bus_address	<= p_address;
		bus_wdata	<= p_data;
		@( posedge clk );

		while( !bus_ready && count < 5 ) begin
			count	<= count + 1;
			@( posedge clk );
		end

		bus_cs		<= 1'b0;
		bus_write	<= 1'b0;
		bus_valid	<= 1'b0;
		@( posedge clk );
	endtask : reg_write



	// --------------------------------------------------------------------
	task check_segment(
		input	[15:0]	p_address,
		input	[7:0]	p_segment
	);
		bus_address		<= p_address;
		@( posedge clk );

		if( mapper_segment == p_segment ) begin
			$display( "[OK] segment( %d ) == %02X", p_address[15:14], p_segment );
		end
		else begin
			$display( "[NG] segment( %d ) == %02X != %02X", p_address[15:14], p_segment, mapper_segment );
		end
		@( posedge clk );
	endtask : check_segment

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		reset_n			= 1'b0;
		clk				= 1'b0;
		bus_cs			= 1'b0;
		bus_write		= 1'b0;
		bus_valid		= 1'b0;
		bus_address		= 16'd0;
		bus_wdata		= 8'd0;

		@( negedge clk );
		@( negedge clk );
		@( posedge clk );

		reset_n			= 1'b1;
		@( posedge clk );
		repeat( 10 ) @( posedge clk );

		$display( "<<TEST001>> Mapper Register Write Test" );
		reg_write( 16'h00FC, 8'h12 );
		reg_write( 16'h00FD, 8'h23 );
		reg_write( 16'h00FE, 8'h34 );
		reg_write( 16'h00FF, 8'h45 );

		$display( "<<TEST002>> Mapper Segment Verify Test" );
		check_segment( 16'h0000, 8'h12 );
		check_segment( 16'h4000, 8'h23 );
		check_segment( 16'h8000, 8'h34 );
		check_segment( 16'hC000, 8'h45 );

		$display( "<<TEST003>> Mapper Register Protect Test" );
		reg_write( 16'h001C, 8'h21 );
		reg_write( 16'h002D, 8'h32 );
		reg_write( 16'h003E, 8'h43 );
		reg_write( 16'h004F, 8'h54 );
		reg_write( 16'h005C, 8'hA5 );
		reg_write( 16'h006D, 8'hA5 );
		reg_write( 16'h007E, 8'hA5 );
		reg_write( 16'h008F, 8'hA5 );
		check_segment( 16'h0000, 8'h12 );
		check_segment( 16'h4000, 8'h23 );
		check_segment( 16'h8000, 8'h34 );
		check_segment( 16'hC000, 8'h45 );

		$display( "<<TEST004>> Mapper Segment Test" );
		check_segment( 16'h0000, 8'h12 );
		check_segment( 16'h4000, 8'h23 );
		check_segment( 16'h8000, 8'h34 );
		check_segment( 16'hC000, 8'h45 );
		check_segment( 16'h8000, 8'h34 );
		check_segment( 16'h4000, 8'h23 );
		check_segment( 16'h0000, 8'h12 );

		$display( "<<TEST005>> Mapper Register Write Test" );
		reg_write( 16'h00FC, 8'hCA );
		reg_write( 16'h00FD, 8'hDB );
		reg_write( 16'h00FE, 8'hEC );
		reg_write( 16'h00FF, 8'hFD );

		$display( "<<TEST006>> Mapper Segment Test" );
		check_segment( 16'h0000, 8'hCA );
		check_segment( 16'h4000, 8'hDB );
		check_segment( 16'h8000, 8'hEC );
		check_segment( 16'hC000, 8'hFD );
		check_segment( 16'h8000, 8'hEC );
		check_segment( 16'h4000, 8'hDB );
		check_segment( 16'h0000, 8'hCA );
		repeat( 10 ) @( posedge clk );

		$finish;
	end
endmodule
