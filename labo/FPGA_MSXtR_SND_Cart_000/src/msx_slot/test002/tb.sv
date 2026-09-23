// -----------------------------------------------------------------------------
//	Test of msx_slot.v + y8960_address_decode.v (connected together)
//	Copyright (C)2026 Takayuki Hara (HRA!)
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
//	This testbench connects msx_slot.v (MSX Slot Signal -> Local BUS) directly
//	to y8960_address_decode.v (Local BUS -> per module chip select) and drives
//	real MSX Slot Signal timing (via p_slot_* / p_slot_clk) to check:
//	  1. Every I/O port and Memory Mapped I/O register that
//	     y8960_address_decode supports is reachable through msx_slot and
//	     asserts exactly the expected single chip select.
//	  2. Any I/O port address that is not supported (not decoded by
//	     y8960_address_decode) asserts no chip select at all (all 0).
//	  3. A Memory access while this cartridge is not slot-selected
//	     (SLTSL not asserted) never reaches the Local BUS, so no chip
//	     select is asserted either.
//-----------------------------------------------------------------------------

module tb ();
	localparam		clk_base		= 1_000_000_000_000.0/42_954_540;	//	ps
	localparam		cpu_clk_base	= 1_000_000_000_000.0/ 3_579_545;	//	ps

	//	I/O port addresses
	localparam	[7:0]	c_ssg1_io		= 8'hA0;
	localparam	[7:0]	c_ssg2_io		= 8'hA2;
	localparam	[7:0]	c_opll1_io		= 8'h7A;
	localparam	[7:0]	c_opll2_io		= 8'h7C;
	localparam	[7:0]	c_opl2_1_io		= 8'hC0;
	localparam	[7:0]	c_opl2_2_io		= 8'hC2;
	localparam	[7:0]	c_dcsg_io		= 8'h7E;
	localparam	[7:0]	c_timer1_io		= 8'hB0;
	localparam	[7:0]	c_timer2_io		= 8'hB2;
	localparam	[7:0]	c_sysctrl_io	= 8'h45;

	//	Memory Mapped I/O addresses (7FE0h-7FFFh window)
	localparam	[15:0]	c_ssg_mio		= 16'h7FEA;
	localparam	[15:0]	c_opl2_1_mio	= 16'h7FEC;
	localparam	[15:0]	c_opl2_2_mio	= 16'h7FEE;
	localparam	[15:0]	c_dcsg_mio		= 16'h7FF0;
	localparam	[15:0]	c_opll1_mio		= 16'h7FF2;
	localparam	[15:0]	c_opll2_mio		= 16'h7FF4;
	localparam	[15:0]	c_io_en1_mio	= 16'h7FF6;
	localparam	[15:0]	c_io_en2_mio	= 16'h7FFF;
	localparam	[15:0]	c_normal_mem	= 16'h8000;

	//	Chip select bit order: { timer, opll, opl2, ssg, scc, dcsg, sysctrl }
	localparam	[6:0]	c_cs_none		= 7'b0000000;
	localparam	[6:0]	c_cs_timer		= 7'b1000000;
	localparam	[6:0]	c_cs_opll		= 7'b0100000;
	localparam	[6:0]	c_cs_opl2		= 7'b0010000;
	localparam	[6:0]	c_cs_ssg		= 7'b0001000;
	localparam	[6:0]	c_cs_scc		= 7'b0000100;
	localparam	[6:0]	c_cs_dcsg		= 7'b0000010;
	localparam	[6:0]	c_cs_sysctrl	= 7'b0000001;

	reg				clk;
	reg				p_slot_clk;
	reg				p_slot_reset_n;
	reg				p_slot_sltsl_n;
	reg				p_slot_memreq_n;
	reg				p_slot_ioreq_n;
	reg				p_slot_wr_n;
	reg				p_slot_rd_n;
	reg		[15:0]	p_slot_address;
	wire	[7:0]	p_slot_data;
	reg		[7:0]	ff_slot_data;
	wire			p_slot_int;
	wire			p_slot_data_dir;
	wire			reset_n;
	reg				int_n;
	wire	[15:0]	bus_address;
	wire			bus_io;
	wire			bus_write;
	wire			bus_valid;
	wire			bus_ready;
	wire	[7:0]	bus_wdata;
	wire			bus_timer_cs;
	wire			bus_opll_cs;
	wire			bus_opl2_cs;
	wire			bus_ssg_cs;
	wire			bus_scc_cs;
	wire			bus_dcsg_cs;
	wire			bus_sysctrl_cs;
	reg				memory_io_en;
	wire	[3:0]	led;
	string			s_state;
	integer			error_count;

	// --------------------------------------------------------------------
	//	DUT: msx_slot -> y8960_address_decode
	// --------------------------------------------------------------------
	msx_slot u_msx_slot (
		.clk					( clk					),
		.reset_n				( reset_n				),
		.p_slot_reset_n			( p_slot_reset_n		),
		.p_slot_sltsl_n			( p_slot_sltsl_n		),
		.p_slot_memreq_n		( p_slot_memreq_n		),
		.p_slot_ioreq_n			( p_slot_ioreq_n		),
		.p_slot_wr_n			( p_slot_wr_n			),
		.p_slot_rd_n			( p_slot_rd_n			),
		.p_slot_address			( p_slot_address		),
		.p_slot_data			( p_slot_data			),
		.p_slot_int				( p_slot_int			),
		.p_slot_data_dir		( p_slot_data_dir		),
		.int_n					( int_n					),
		.bus_address			( bus_address			),
		.bus_io					( bus_io				),
		.bus_write				( bus_write				),
		.bus_valid				( bus_valid				),
		.bus_ready				( bus_ready				),
		.bus_wdata				( bus_wdata				),
		.bus_rdata				( 8'h00					),
		.bus_rdata_en			( 1'b0					)
	);

	y8960_address_decode u_y8960_address_decode (
		.clk					( clk					),
		.reset_n				( reset_n				),
		.bus_address			( bus_address			),
		.bus_io					( bus_io				),
		.bus_write				( bus_write				),
		.bus_valid				( bus_valid				),
		.bus_ready				( bus_ready				),
		.bus_wdata				( bus_wdata				),
		.bus_timer_cs			( bus_timer_cs			),
		.bus_opll_cs			( bus_opll_cs			),
		.bus_opl2_cs			( bus_opl2_cs			),
		.bus_ssg_cs				( bus_ssg_cs			),
		.bus_scc_cs				( bus_scc_cs			),
		.bus_dcsg_cs			( bus_dcsg_cs			),
		.bus_sysctrl_cs			( bus_sysctrl_cs		),
		.bus_timer_ready		( 1'b1					),
		.bus_opll_ready			( 1'b1					),
		.bus_opl2_ready			( 1'b1					),
		.bus_ssg_ready			( 1'b1					),
		.bus_scc_ready			( 1'b1					),
		.bus_dcsg_ready			( 1'b1					),
		.bus_sysctrl_ready		( 1'b1					),
		.memory_io_en			( memory_io_en			),
		.led					( led					)
	);

	//	1: Read, 0: Write
	assign p_slot_data	= (p_slot_data_dir == 1'b1) ? 8'hZZ: ff_slot_data;

	// --------------------------------------------------------------------
	//	clock
	// --------------------------------------------------------------------
	always #(clk_base/2) begin
		clk <= ~clk;
	end

	// --------------------------------------------------------------------
	//	Local BUS transaction monitor (captures the first cycle of each
	//	transaction: MSX Slot Signal -> Local BUS -> chip select result)
	// --------------------------------------------------------------------
	reg				ff_prev_valid = 1'b0;
	reg		[15:0]	ff_cap_address;
	reg		[7:0]	ff_cap_wdata;
	reg				ff_cap_io;
	reg				ff_cap_write;
	reg		[6:0]	ff_cap_cs;

	always @( posedge clk ) begin
		ff_prev_valid	<= bus_valid;
		if( bus_valid && !ff_prev_valid ) begin
			ff_cap_address	<= bus_address;
			ff_cap_wdata	<= bus_wdata;
			ff_cap_io		<= bus_io;
			ff_cap_write	<= bus_write;
			ff_cap_cs		<= { bus_timer_cs, bus_opll_cs, bus_opl2_cs, bus_ssg_cs, bus_scc_cs, bus_dcsg_cs, bus_sysctrl_cs };
		end
	end

	//	Free running bus_valid monitor, used to prove that a Memory access
	//	while this cartridge is not slot-selected never reaches the Local BUS.
	reg				ff_saw_bus_valid = 1'b0;

	always @( posedge clk ) begin
		if( bus_valid ) begin
			ff_saw_bus_valid	<= 1'b1;
		end
	end

	// --------------------------------------------------------------------
	//	check
	// --------------------------------------------------------------------
	task check(
		input string	name,
		input			condition
	);
		if( condition ) begin
			$display( "OK   : %s", name );
		end
		else begin
			$display( "ERROR: %s", name );
			error_count = error_count + 1;
		end
	endtask

	// --------------------------------------------------------------------
	//	Force msx_slot's internal Local BUS handshake back to idle.
	//	(Needed after an access that no module claims, since bus_ready then
	//	never comes back and msx_slot would otherwise stay busy forever.)
	// --------------------------------------------------------------------
	task pulse_reset();
		p_slot_reset_n	= 1'b0;
		@( posedge clk );
		@( posedge clk );
		p_slot_reset_n	= 1'b1;
		@( posedge clk );
		@( posedge clk );
	endtask

	// --------------------------------------------------------------------
	//	I/O write access (MSX Slot Signal timing, basic slot)
	// --------------------------------------------------------------------
	task write_io(
		input	[7:0]	address,
		input	[7:0]	wdata,
		input	[6:0]	expected_cs,
		input string	name
	);
		fork
			//	CPU clock
			begin
				//	T1
				s_state		= "T1";
				p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T2
				s_state		= "T2";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	TW
				s_state		= "TW";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T3
				s_state		= "T3";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T4
				s_state		= "T4";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T5
				s_state		= "T5";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
			end
			//	Address
			begin
				#170ns p_slot_address = address;
			end
			//	/IORQ
			begin
				p_slot_ioreq_n = 1'b1;
				//	T1
				@( negedge p_slot_clk );
				@( posedge p_slot_clk );
				#135ns p_slot_ioreq_n = 1'b0;
				@( negedge p_slot_clk );
				@( negedge p_slot_clk );
				@( negedge p_slot_clk );
				#145ns p_slot_ioreq_n = 1'b1;
			end
			//	/WR
			begin
				p_slot_wr_n = 1'b1;
				//	T1
				@( negedge p_slot_clk );
				@( posedge p_slot_clk );
				#125ns p_slot_wr_n = 1'b0;
				@( negedge p_slot_clk );
				@( negedge p_slot_clk );
				@( negedge p_slot_clk );
				#120ns p_slot_wr_n = 1'b1;
			end
			//	others
			begin
				ff_slot_data	= wdata;
			end
		join
		check( $sformatf( "write_io %-12s address=%02h wdata=%02h expected_cs=%07b actual_cs=%07b", name, address, wdata, expected_cs, ff_cap_cs ),
			(ff_cap_io == 1'b1) && (ff_cap_write == 1'b1) && (ff_cap_address[7:0] == address) && (ff_cap_wdata == wdata) && (ff_cap_cs == expected_cs) );
		if( expected_cs == c_cs_none ) begin
			//	No module claims this port, bus_ready never comes back:
			//	bring the Local BUS handshake back to idle before continuing.
			pulse_reset();
		end
		else begin
			repeat( 4 ) @( posedge clk );
			check( $sformatf( "write_io %-12s bus_valid returned to idle", name ), bus_valid == 1'b0 );
		end
	endtask

	// --------------------------------------------------------------------
	//	I/O read access (MSX Slot Signal timing, basic slot)
	// --------------------------------------------------------------------
	task read_io(
		input	[7:0]	address,
		input	[6:0]	expected_cs,
		input string	name
	);
		reg	[7:0]	rdata;
		fork
			//	CPU clock
			begin
				//	T1
				s_state		= "T1";
				p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T2
				s_state		= "T2";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	TW
				s_state		= "TW";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T3
				s_state		= "T3";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T4
				s_state		= "T4";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T5
				s_state		= "T5";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
			end
			//	Address
			begin
				#170ns p_slot_address = address;
			end
			//	/IORQ
			begin
				p_slot_ioreq_n = 1'b1;
				//	T1
				@( negedge p_slot_clk );
				@( posedge p_slot_clk );
				#135ns p_slot_ioreq_n = 1'b0;
				@( negedge p_slot_clk );
				@( negedge p_slot_clk );
				@( negedge p_slot_clk );
				#145ns p_slot_ioreq_n = 1'b1;
			end
			//	/RD
			begin
				p_slot_rd_n = 1'b1;
				//	T1
				@( negedge p_slot_ioreq_n );
				#10ns p_slot_rd_n = 1'b0;
				@( posedge p_slot_ioreq_n );
				rdata = p_slot_data;
				p_slot_rd_n = 1'b1;
			end
		join
		check( $sformatf( "read_io  %-12s address=%02h expected_cs=%07b actual_cs=%07b", name, address, expected_cs, ff_cap_cs ),
			(ff_cap_io == 1'b1) && (ff_cap_write == 1'b0) && (ff_cap_address[7:0] == address) && (ff_cap_cs == expected_cs) );
		if( expected_cs == c_cs_none ) begin
			pulse_reset();
		end
		else begin
			repeat( 4 ) @( posedge clk );
			check( $sformatf( "read_io  %-12s bus_valid returned to idle", name ), bus_valid == 1'b0 );
		end
	endtask

	// --------------------------------------------------------------------
	//	Memory write access (MSX Slot Signal timing, basic slot).
	//	assert_sltsl=0 : this cartridge is not slot-selected for the address
	//	                 (models "that address belongs to another slot"),
	//	                 so bus_valid must never be asserted at all.
	// --------------------------------------------------------------------
	task write_mem(
		input	[15:0]	address,
		input	[7:0]	wdata,
		input	[6:0]	expected_cs,
		input			assert_sltsl,
		input string	name
	);
		ff_saw_bus_valid = 1'b0;
		fork
			//	CPU clock
			begin
				//	T1
				s_state		= "T1";
				p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T2
				s_state		= "T2";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	TW
				s_state		= "TW";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T3
				s_state		= "T3";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T4
				s_state		= "T4";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
				//	T5
				s_state		= "T5";
				#(cpu_clk_base/2) p_slot_clk	= 1'b1;
				#(cpu_clk_base/2) p_slot_clk	= 1'b0;
			end
			//	Address
			begin
				#170ns p_slot_address = address;
			end
			//	/MREQ, /SLTSL
			begin
				p_slot_memreq_n	= 1'b1;
				p_slot_sltsl_n	= 1'b1;
				//	T1
				@( negedge p_slot_clk );
				@( posedge p_slot_clk );
				#135ns begin
					p_slot_memreq_n	= 1'b0;
					p_slot_sltsl_n	= assert_sltsl ? 1'b0 : 1'b1;
				end
				@( negedge p_slot_clk );
				@( negedge p_slot_clk );
				@( negedge p_slot_clk );
				#145ns begin
					p_slot_memreq_n	= 1'b1;
					p_slot_sltsl_n	= 1'b1;
				end
			end
			//	/WR
			begin
				p_slot_wr_n = 1'b1;
				//	T1
				@( negedge p_slot_clk );
				@( posedge p_slot_clk );
				#125ns p_slot_wr_n = 1'b0;
				@( negedge p_slot_clk );
				@( negedge p_slot_clk );
				@( negedge p_slot_clk );
				#120ns p_slot_wr_n = 1'b1;
			end
			//	others
			begin
				ff_slot_data	= wdata;
			end
		join
		if( !assert_sltsl ) begin
			check( $sformatf( "write_mem %-12s (SLTSL not asserted) bus_valid never asserted", name ), ff_saw_bus_valid == 1'b0 );
			check( $sformatf( "write_mem %-12s (SLTSL not asserted) all cs == 0", name ),
				{ bus_timer_cs, bus_opll_cs, bus_opl2_cs, bus_ssg_cs, bus_scc_cs, bus_dcsg_cs, bus_sysctrl_cs } == c_cs_none );
		end
		else begin
			check( $sformatf( "write_mem %-12s address=%04h wdata=%02h expected_cs=%07b actual_cs=%07b", name, address, wdata, expected_cs, ff_cap_cs ),
				(ff_cap_io == 1'b0) && (ff_cap_write == 1'b1) && (ff_cap_address == address) && (ff_cap_wdata == wdata) && (ff_cap_cs == expected_cs) );
			repeat( 4 ) @( posedge clk );
			check( $sformatf( "write_mem %-12s bus_valid returned to idle", name ), bus_valid == 1'b0 );
		end
	endtask

	// --------------------------------------------------------------------
	//	Enable an I/O port group through the memory mapped enabler registers
	// --------------------------------------------------------------------
	task write_io_enabler(
		input	[15:0]	address,
		input	[7:0]	wdata
	);
		write_mem( address, wdata, c_cs_none, 1'b1, "io_enabler" );
	endtask

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		clk					= 0;			//	42.95454MHz
		p_slot_clk			= 0;
		p_slot_reset_n		= 1'b0;
		p_slot_sltsl_n		= 1;
		p_slot_memreq_n		= 1;
		p_slot_ioreq_n		= 1;
		p_slot_wr_n			= 1;
		p_slot_rd_n			= 1;
		p_slot_address		= 0;
		int_n				= 1;
		memory_io_en		= 1'b0;
		error_count			= 0;

		@( posedge clk );
		@( posedge clk );

		p_slot_reset_n		= 1'b1;
		@( posedge clk );
		@( posedge clk );

		memory_io_en		= 1'b1;

		// --------------------------------------------------------------------
		//	Enable every I/O port through the memory mapped enabler registers
		//	(ssg / opll1 are already enabled by reset default).
		// --------------------------------------------------------------------
		write_io_enabler( c_io_en1_mio, 8'b0000_0011 );	//	opll1_io_en, opll2_io_en
		write_io_enabler( c_io_en2_mio, 8'b1001_1111 );	//	opl2_1/2, dcsg1/2, ssg, timer

		// --------------------------------------------------------------------
		//	Supported I/O access
		// --------------------------------------------------------------------
		write_io( c_ssg1_io,    8'h11, c_cs_ssg,     "ssg1"     );
		write_io( c_ssg2_io,    8'h12, c_cs_ssg,     "ssg2"     );
		write_io( c_opll1_io,   8'h13, c_cs_opll,    "opll1"    );
		write_io( c_opll2_io,   8'h14, c_cs_opll,    "opll2"    );
		write_io( c_opl2_1_io,  8'h15, c_cs_opl2,    "opl2_1"   );
		write_io( c_opl2_2_io,  8'h16, c_cs_opl2,    "opl2_2"   );
		write_io( c_dcsg_io,    8'h17, c_cs_dcsg,    "dcsg"     );
		write_io( c_timer1_io,  8'h18, c_cs_timer,   "timer1"   );
		write_io( c_timer2_io,  8'h19, c_cs_timer,   "timer2"   );
		write_io( c_sysctrl_io, 8'h1A, c_cs_sysctrl, "sysctrl"  );

		read_io( c_ssg1_io,    c_cs_ssg,     "ssg1"     );
		read_io( c_opll1_io,   c_cs_opll,    "opll1"    );
		read_io( c_opl2_1_io,  c_cs_opl2,    "opl2_1"   );
		read_io( c_dcsg_io,    c_cs_dcsg,    "dcsg"     );
		read_io( c_timer1_io,  c_cs_timer,   "timer1"   );
		read_io( c_sysctrl_io, c_cs_sysctrl, "sysctrl"  );

		// --------------------------------------------------------------------
		//	Supported Memory access (Memory Mapped I/O window + plain memory)
		// --------------------------------------------------------------------
		write_mem( c_ssg_mio,     8'h21, c_cs_ssg,  1'b1, "ssg_mio"    );
		write_mem( c_opl2_1_mio,  8'h22, c_cs_opl2, 1'b1, "opl2_1_mio" );
		write_mem( c_opl2_2_mio,  8'h23, c_cs_opl2, 1'b1, "opl2_2_mio" );
		write_mem( c_dcsg_mio,    8'h24, c_cs_dcsg, 1'b1, "dcsg_mio"   );
		write_mem( c_opll1_mio,   8'h25, c_cs_opll, 1'b1, "opll1_mio"  );
		write_mem( c_opll2_mio,   8'h26, c_cs_opll, 1'b1, "opll2_mio"  );
		write_mem( c_normal_mem,  8'h27, c_cs_scc,  1'b1, "normal_mem" );

		// --------------------------------------------------------------------
		//	Unsupported I/O address: no module in y8960_address_decode claims
		//	it, so every chip select must stay 0.
		// --------------------------------------------------------------------
		write_io( 8'h00, 8'h55, c_cs_none, "unmapped_00" );
		write_io( 8'h10, 8'h56, c_cs_none, "unmapped_10" );
		write_io( 8'hD0, 8'h57, c_cs_none, "unmapped_D0" );
		write_io( 8'hFF, 8'h58, c_cs_none, "unmapped_FF" );
		read_io ( 8'h00,        c_cs_none, "unmapped_00" );

		// --------------------------------------------------------------------
		//	Memory access while this cartridge is not slot-selected (SLTSL
		//	stays high): the Local BUS must never receive the access, so no
		//	chip select is asserted either.
		// --------------------------------------------------------------------
		write_mem( 16'h0000, 8'h61, c_cs_none, 1'b0, "no_sltsl_0000" );
		write_mem( 16'h8000, 8'h62, c_cs_none, 1'b0, "no_sltsl_8000" );
		write_mem( c_ssg_mio, 8'h63, c_cs_none, 1'b0, "no_sltsl_ssg_mio" );

		repeat( 10 ) @( posedge clk );

		if( error_count == 0 ) begin
			$display( "OK   : all tests passed" );
		end
		else begin
			$display( "ERROR: %0d test(s) failed", error_count );
		end
		$finish;
	end
endmodule
