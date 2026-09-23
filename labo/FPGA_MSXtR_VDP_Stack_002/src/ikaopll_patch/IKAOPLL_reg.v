// --------------------------------------------------------------------
//  ROM Font Switching Function Add-on Patch
// ====================================================================
//  Copyright 2025 t.hara
// --------------------------------------------------------------------
//  This patch adds a feature to IKAOPLL that allows switching between 
//  four free ROM fonts published below.
//  https://github.com/plgDavid/misc/wiki/Copyright-free-OPLL(x)-ROM-patches
// --------------------------------------------------------------------

module IKAOPLL_reg #(parameter FULLY_SYNCHRONOUS = 1, parameter ALTPATCH_CONFIG_MODE = 0, parameter INSTROM_STYLE = 0) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock
    input   wire            i_phiM_PCEN_n,

    //master reset
    input   wire            i_RST_n,

    //internal clock
    input   wire            i_phi1_PCEN_n, //positive edge clock enable for emulation
    input   wire            i_phi1_NCEN_n, //negative edge clock enable for emulation

    //CPU bus signals
    input   wire            i_CS_n,
    input   wire            i_WR_n,
    input   wire            i_A0,
    
    input   wire    [7:0]   i_D,
    output  wire    [1:0]   o_D,
    output  wire            o_D_OE,

    //VRC7 patch enable pin
    input   wire            i_ALTPATCH_EN,

    //timings
    input   wire            i_CYCLE_00, i_CYCLE_12, i_CYCLE_21, i_CYCLE_D3_ZZ, i_CYCLE_D4_ZZ, i_MnC_SEL,

    //ROM outputs
    output  wire    [3:0]   o_TEST,
    output  wire            o_RHYTHM_EN,
    output  wire    [8:0]   o_FNUM,
    output  wire    [2:0]   o_BLOCK,
    output  reg             o_KON,
    output  wire            o_SUSEN,
    output  reg     [5:0]   o_TL,
    output  reg             o_DC, o_DM,
    output  reg     [2:0]   o_FB,
    output  reg             o_AM, o_PM, o_ETYP, o_KSR,
    output  reg     [3:0]   o_MUL,
    output  reg     [1:0]   o_KSL,
    output  wire    [3:0]   o_AR, o_DR, o_RR,
    output  reg     [3:0]   o_SL,

    //misc
    output  wire            o_EG_ENVCNTR_TEST_DATA,
    input   wire    [9:0]   i_REG_TEST_PHASE,
    input   wire    [6:0]   i_REG_TEST_ATTNLV,
    input   wire    [8:0]   i_REG_TEST_SNDDATA
);



///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            emuclk = i_EMUCLK;
wire            phiMpcen_n = i_phiM_PCEN_n;
wire            phi1pcen_n = i_phi1_PCEN_n;
wire            phi1ncen_n = i_phi1_NCEN_n;

assign  o_D_OE = |{i_CS_n, ~i_WR_n, i_A0, ~i_RST_n};



///////////////////////////////////////////////////////////
//////  Write request synchronizer
////

wire            addrreg_wrrq, datareg_wrrq;
IKAOPLL_rw_synchronizer #(.FULLY_SYNCHRONOUS(FULLY_SYNCHRONOUS)) u_sync_addrreg(
    .i_EMUCLK(emuclk), .i_phiM_PCEN_n(phiMpcen_n), .i_phi1_PCEN_n(phi1pcen_n), .i_phi1_NCEN_n(phi1ncen_n),
    .i_RST_n(i_RST_n), .i_IN(~|{i_CS_n, i_WR_n, i_A0}), .o_OUT(addrreg_wrrq)
);
IKAOPLL_rw_synchronizer #(.FULLY_SYNCHRONOUS(FULLY_SYNCHRONOUS)) u_sync_datareg(
    .i_EMUCLK(emuclk), .i_phiM_PCEN_n(phiMpcen_n), .i_phi1_PCEN_n(phi1pcen_n), .i_phi1_NCEN_n(phi1ncen_n),
    .i_RST_n(i_RST_n), .i_IN(~|{i_CS_n, i_WR_n, ~i_A0}), .o_OUT(datareg_wrrq)
);



///////////////////////////////////////////////////////////
//////  Temporary data latch
////

wire    [7:0]   dbus_inlatch;
assign  o_EG_ENVCNTR_TEST_DATA = dbus_inlatch[2];

generate
if(FULLY_SYNCHRONOUS == 0) begin : FULLY_SYNCHRONOUS_0_inlatch

wire    [7:0]   dbus_inlatch_temp;
IKAOPLL_dlatch #(.WIDTH(8)) u_dbus_inlatch_temp (
    .i_EN(~|{i_CS_n, i_WR_n, ~i_RST_n}), .i_D(i_D), .o_Q(dbus_inlatch_temp)
);

assign  dbus_inlatch = dbus_inlatch_temp;

end
else begin : FULLY_SYNCHRONOUS_1_inlatch

reg     [7:0]   din_syncchain[0:1];
reg     [1:0]   cs_n_syncchain, wr_n_syncchain;
reg     [7:0]   dbus_inlatch_temp;

//make alias signals
wire            cs_n = cs_n_syncchain[1];
wire            wr_n = wr_n_syncchain[1];
wire    [7:0]   din = din_syncchain[1];

always @(posedge emuclk) begin
    din_syncchain[0] <= i_D;
    din_syncchain[1] <= din_syncchain[0];

    cs_n_syncchain[0] <= i_CS_n;
    cs_n_syncchain[1] <= cs_n_syncchain[0];

    wr_n_syncchain[0] <= i_WR_n;
    wr_n_syncchain[1] <= wr_n_syncchain[0];

    if(~|{cs_n, wr_n}) dbus_inlatch_temp <= din;
end

assign  dbus_inlatch = dbus_inlatch_temp;
    
end
endgenerate



///////////////////////////////////////////////////////////
//////  D1REG - parameter*1 register
////

//latch D1REG address, the original chip latches "decoded" register select bits
reg     [7:0]   d1reg_addr;
always @(posedge emuclk) if(!phi1ncen_n) if(addrreg_wrrq) d1reg_addr <= dbus_inlatch;

//D1REG pair, 0=modulator 1=carrier
reg     [1:0]   am_reg, pm_reg, etyp_reg, ksr_reg;
reg     [3:0]   mul_reg[0:1];
reg     [1:0]   ksl_reg[0:1];
reg     [3:0]   ar_reg[0:1];
reg     [3:0]   dr_reg[0:1];
reg     [3:0]   sl_reg[0:1];
reg     [3:0]   rr_reg[0:1];

//D1REG single
reg     [5:0]   tl_reg;
reg             dc_reg, dm_reg;
reg     [2:0]   fb_reg;
reg     [3:0]   test_reg;
reg     [5:0]   rhythm_reg;

assign  o_TEST = test_reg;
assign  o_RHYTHM_EN = rhythm_reg[5];

`ifdef IKAOPLL_ASYNC_RST
always @(posedge emuclk or negedge i_RST_n)
`else
always @(posedge emuclk)
`endif
begin
    if(!i_RST_n) begin
        am_reg <= 2'b00; pm_reg <= 2'b00; etyp_reg <= 2'b00; ksr_reg <= 2'b00;
        mul_reg[0] <= 4'd0; mul_reg[1] <= 4'd0;
        ksl_reg[0] <= 2'd0; ksl_reg[1] <= 2'd0;
        ar_reg[0] <= 4'd0; ar_reg[1] <= 4'd0;
        dr_reg[0] <= 4'd0; dr_reg[1] <= 4'd0;
        sl_reg[0] <= 4'd0; sl_reg[1] <= 4'd0;
        rr_reg[0] <= 4'd0; rr_reg[1] <= 4'd0;

        tl_reg <= 6'd0;
        dc_reg <= 1'b0; dm_reg <= 1'b0;
        fb_reg <= 1'b0;
        test_reg <= 4'b0000;
        rhythm_reg <= 6'b000000;
    end
    else begin if(!phi1ncen_n) begin
        if(datareg_wrrq) begin
                 if(d1reg_addr == 8'h0) {am_reg[0], pm_reg[0], etyp_reg[0], ksr_reg[0], mul_reg[0]} <= dbus_inlatch;
            else if(d1reg_addr == 8'h1) {am_reg[1], pm_reg[1], etyp_reg[1], ksr_reg[1], mul_reg[1]} <= dbus_inlatch;
            else if(d1reg_addr == 8'h2) {ksl_reg[0], tl_reg} <= dbus_inlatch;
            else if(d1reg_addr == 8'h3) {ksl_reg[1], dc_reg, dm_reg, fb_reg} <= {dbus_inlatch[7:6], dbus_inlatch[4:0]};
            else if(d1reg_addr == 8'h4) {ar_reg[0], dr_reg[0]} <= dbus_inlatch;
            else if(d1reg_addr == 8'h5) {ar_reg[1], dr_reg[1]} <= dbus_inlatch;
            else if(d1reg_addr == 8'h6) {sl_reg[0], rr_reg[0]} <= dbus_inlatch;
            else if(d1reg_addr == 8'h7) {sl_reg[1], rr_reg[1]} <= dbus_inlatch;
            else if(d1reg_addr == 8'hE) rhythm_reg <= dbus_inlatch[5:0];
            else if(d1reg_addr == 8'hF) test_reg <= dbus_inlatch[3:0];
        end
    end end
end



///////////////////////////////////////////////////////////
//////  D9REG - parameter*9 register
////

//latch D9REG address
reg     [6:0]   d9reg_addr;
always @(posedge emuclk) if(!phi1ncen_n) if(addrreg_wrrq && dbus_inlatch[7] == 1'b0) d9reg_addr <= dbus_inlatch[6:0];

//D9REG enable
reg             d9reg_en;
always @(posedge emuclk) begin
    if(!i_RST_n) d9reg_en <= 1'b0;
    else begin if(!phi1ncen_n) begin
        if(addrreg_wrrq) d9reg_en <= dbus_inlatch[7:6] == 2'b00;
    end end
end

//latch D9REG data
reg     [7:0]   d9reg_data;
always @(posedge emuclk) begin
    if(!i_RST_n) d9reg_data <= 8'h00;
    else begin if(!phi1ncen_n) begin
        if(d9reg_en && datareg_wrrq) d9reg_data <= dbus_inlatch;
    end end
end

//D9REG address counter
reg     [4:0]   d9reg_addrcntr;
always @(posedge emuclk) if(!phi1ncen_n) begin
    if(i_CYCLE_21) d9reg_addrcntr <= 5'd0;
    else d9reg_addrcntr <= d9reg_addrcntr + 5'd1;
end

//D9REG write data queued flag
reg             d9reg_wrdata_queued_n; // = 1'b1;
wire            trace_d9reg_addrcntr = ~|{~i_RST_n, addrreg_wrrq, d9reg_wrdata_queued_n};
always @(posedge emuclk) if(!phi1ncen_n) begin
    d9reg_wrdata_queued_n <= ~(trace_d9reg_addrcntr | (d9reg_en && datareg_wrrq));
end

//address match signal
wire            d9reg_addr_match = ~d9reg_addrcntr[4] & (d9reg_addrcntr[3:0] == d9reg_addr[3:0]) & trace_d9reg_addrcntr;

//D9REG enable signals
wire            reg10_18_en = ((d9reg_addr[6:4] == 3'b001) & d9reg_addr_match) | ~i_RST_n;
wire            reg20_28_en = ((d9reg_addr[6:4] == 3'b010) & d9reg_addr_match) | ~i_RST_n;
wire            reg30_38_en = ((d9reg_addr[6:4] == 3'b011) & d9reg_addr_match) | ~i_RST_n;
wire            reg40_48_en = ((d9reg_addr[6:4] == 3'b100) & d9reg_addr_match) | ~i_RST_n;
//D9REG
wire            kon_reg;
wire    [3:0]   vol_reg, inst_reg;
wire    [1:0]   bank_reg;

IKAOPLL_d9reg #(8) u_fnum_lsbs (.i_EMUCLK(emuclk), .i_phi1_NCEN_n(phi1ncen_n), 
                                .i_EN(reg10_18_en), .i_TAPSEL({i_CYCLE_D4_ZZ, i_CYCLE_D3_ZZ}), .i_D(i_RST_n ? d9reg_data : 8'd0), .o_Q(o_FNUM[7:0]));

IKAOPLL_d9reg #(1) u_fnum_msb  (.i_EMUCLK(emuclk), .i_phi1_NCEN_n(phi1ncen_n), 
                                .i_EN(reg20_28_en), .i_TAPSEL({i_CYCLE_D4_ZZ, i_CYCLE_D3_ZZ}), .i_D(i_RST_n ? d9reg_data[0]: 1'b0), .o_Q(o_FNUM[8]));

IKAOPLL_d9reg #(3) u_block     (.i_EMUCLK(emuclk), .i_phi1_NCEN_n(phi1ncen_n), 
                                .i_EN(reg20_28_en), .i_TAPSEL({i_CYCLE_D4_ZZ, i_CYCLE_D3_ZZ}), .i_D(i_RST_n ? d9reg_data[3:1] : 3'd0), .o_Q(o_BLOCK));

IKAOPLL_d9reg #(1) u_kon       (.i_EMUCLK(emuclk), .i_phi1_NCEN_n(phi1ncen_n), 
                                .i_EN(reg20_28_en), .i_TAPSEL({i_CYCLE_D4_ZZ, i_CYCLE_D3_ZZ}), .i_D(i_RST_n ? d9reg_data[4] : 1'b0), .o_Q(kon_reg));

IKAOPLL_d9reg #(1) u_susen     (.i_EMUCLK(emuclk), .i_phi1_NCEN_n(phi1ncen_n), 
                                .i_EN(reg20_28_en), .i_TAPSEL({i_CYCLE_D4_ZZ, i_CYCLE_D3_ZZ}), .i_D(i_RST_n ? d9reg_data[5] : 1'b0), .o_Q(o_SUSEN));

IKAOPLL_d9reg #(4) u_vol       (.i_EMUCLK(emuclk), .i_phi1_NCEN_n(phi1ncen_n), 
                                .i_EN(reg30_38_en), .i_TAPSEL({i_CYCLE_D4_ZZ, i_CYCLE_D3_ZZ}), .i_D(i_RST_n ? d9reg_data[3:0] : 4'd0), .o_Q(vol_reg));

IKAOPLL_d9reg #(4) u_inst      (.i_EMUCLK(emuclk), .i_phi1_NCEN_n(phi1ncen_n), 
                                .i_EN(reg30_38_en), .i_TAPSEL({i_CYCLE_D4_ZZ, i_CYCLE_D3_ZZ}), .i_D(i_RST_n ? d9reg_data[7:4] : 4'd0), .o_Q(inst_reg));

IKAOPLL_d9reg #(2) u_bank      (.i_EMUCLK(emuclk), .i_phi1_NCEN_n(phi1ncen_n), 
                                .i_EN(reg40_48_en), .i_TAPSEL({i_CYCLE_D4_ZZ, i_CYCLE_D3_ZZ}), .i_D(i_RST_n ? d9reg_data[1:0] : 2'd0), .o_Q(bank_reg));


///////////////////////////////////////////////////////////
//////  INSTRUMENT ROM
////

//percussion process sequencer
reg             cyc13;
always @(posedge i_EMUCLK) if(!phi1ncen_n) cyc13 <= i_CYCLE_12;

wire            perc_proc_d = rhythm_reg[5] & cyc13;
reg     [4:0]   perc_proc;
always @(posedge i_EMUCLK) if(!phi1ncen_n) begin
    perc_proc[0] <= perc_proc_d;
    perc_proc[4:1] <= perc_proc[3:0];
end

//wires
wire            am_rom, pm_rom, etyp_rom, ksr_rom;
wire    [3:0]   mul_rom;
wire    [1:0]   ksl_rom;
wire    [3:0]   ar_rom;
wire    [3:0]   dr_rom;
wire    [3:0]   sl_rom;
wire    [3:0]   rr_rom;
wire    [5:0]   tl_rom;
wire            dc_rom, dm_rom;
wire    [2:0]   fb_rom;

//ROM module
IKAOPLL_instrom #(INSTROM_STYLE) u_instrom (
    //chip clock
    .i_EMUCLK                   (emuclk                     ),
    .i_phi1_PCEN_n              (phi1pcen_n                 ),
    .i_INST_BANK                (bank_reg                   ),
    .i_INST_ADDR                (inst_reg                   ),
    .i_BD0_SEL(perc_proc_d), .i_HH_SEL(perc_proc[0]), .i_TT_SEL(perc_proc[1]), .i_BD1_SEL(perc_proc[2]), .i_SD_SEL(perc_proc[3]), .i_TC_SEL(perc_proc[4]), 
    .i_MnC_SEL(i_MnC_SEL),

    .o_TL_ROM(tl_rom), .o_DC_ROM(dc_rom), .o_DM_ROM(dm_rom), .o_FB_ROM(fb_rom),
    .o_AM_ROM(am_rom), .o_PM_ROM(pm_rom), .o_ETYP_ROM(etyp_rom), .o_KSR_ROM(ksr_rom),
    .o_MUL_ROM(mul_rom), .o_KSL_ROM(ksl_rom),
    .o_AR_ROM(ar_rom), .o_DR_ROM(dr_rom), .o_SL_ROM(sl_rom), .o_RR_ROM(rr_rom)
);



///////////////////////////////////////////////////////////
//////  RHYTHM KON SELECTOR
////

always @(*) begin
    /*
    case({perc_proc_d, perc_proc[0], perc_proc[1], perc_proc[2], perc_proc[3], perc_proc[4]})
        6'b100000: o_KON = rhythm_reg[4] | kon_reg;
        6'b010000: o_KON = rhythm_reg[0] | kon_reg;
        6'b001000: o_KON = rhythm_reg[2] | kon_reg;
        6'b000100: o_KON = rhythm_reg[4] | kon_reg;
        6'b000010: o_KON = rhythm_reg[3] | kon_reg;
        6'b000001: o_KON = rhythm_reg[1] | kon_reg;
        default:   o_KON = kon_reg;
    endcase
    */

    o_KON = (rhythm_reg[4] & perc_proc_d) |
            (rhythm_reg[0] & perc_proc[0]) |
            (rhythm_reg[2] & perc_proc[1]) |
            (rhythm_reg[4] & perc_proc[2]) |
            (rhythm_reg[3] & perc_proc[3]) | 
            (rhythm_reg[1] & perc_proc[4]) | 
            kon_reg;
end



///////////////////////////////////////////////////////////
//////  OUTPUT DATA SELECTOR
////

wire            cust_inst_sel = ~|{perc_proc_d, perc_proc[0], perc_proc[1], perc_proc[2], perc_proc[3], perc_proc[4]} & inst_reg == 4'h0;

reg             m_nc_sel_z, cust_inst_sel_z;
always @(posedge i_EMUCLK) if(!phi1pcen_n) begin //positive!!!
    m_nc_sel_z <= i_MnC_SEL;
    cust_inst_sel_z <= cust_inst_sel;
end

//custom instrument parameter register(d1reg) output enables
wire            reg_mod_oe = cust_inst_sel_z &  m_nc_sel_z; //register-modulator OE
wire            reg_car_oe = cust_inst_sel_z & ~m_nc_sel_z; //register-carrier OE
wire            fdbk_reg_oe = cust_inst_sel_z; //instrument register OE

//channel instrument/volume register(d9reg) output latch enables, for percussion volume processing
wire            vol_latch_oe = ~m_nc_sel_z; //volume register outlatch OE
reg             inst_latch_oe;
always @(posedge i_EMUCLK) if(!phi1pcen_n) inst_latch_oe <= perc_proc[0] | perc_proc[1];

//built-in instrument parameter ROM output enables
wire            rom_general_oe = ~cust_inst_sel_z;
wire            tl_rom_oe = ~|{inst_latch_oe, reg_mod_oe, vol_latch_oe};

//percussion level latch
reg     [3:0]   vol_reg_latch, inst_reg_latch;
always @(posedge i_EMUCLK) if(!phi1pcen_n) vol_reg_latch <= vol_reg;
always @(posedge i_EMUCLK) if(!phi1pcen_n) inst_reg_latch <= inst_reg;

//EG parameter mask bit
reg             kon_z;
always @(posedge i_EMUCLK) if(!phi1pcen_n) begin
    kon_z <= o_KON;
end
wire            force_egparam_zero = ~inst_latch_oe & m_nc_sel_z & ~kon_z;

//for simulation
`ifdef IKAOPLL_DEFINE_IDLE_BUS_Z
`define IB 1'bz
`else
`define IB 1'b0
`endif

//mask parameter if needed
reg     [3:0]   ar_muxed, dr_muxed, rr_muxed;
assign  o_AR = force_egparam_zero ? 4'd0 : ar_muxed;
assign  o_DR = force_egparam_zero ? 4'd0 : dr_muxed;
assign  o_RR = force_egparam_zero ? 4'd0 : rr_muxed;

//output selector
always @(*) begin
    //total level(bit complex)
    case({tl_rom_oe, reg_mod_oe, vol_latch_oe, inst_latch_oe})
        4'b1000: o_TL = tl_rom;
        4'b0100: o_TL = tl_reg;
        4'b0010: o_TL = {vol_reg_latch, 2'b00};
        4'b0001: o_TL = {inst_reg_latch, 2'b00};
        default: o_TL = {6{`IB}};
    endcase

    case({rom_general_oe, fdbk_reg_oe})
        2'b10:   begin o_DC = dc_rom; o_DM = dm_rom; o_FB = fb_rom; end
        2'b01:   begin o_DC = dc_reg; o_DM = dm_reg; o_FB = fb_reg; end
        default: begin o_DC = `IB; o_DM = `IB; o_FB = {3{`IB}}; end
    endcase

    case({rom_general_oe, reg_mod_oe, reg_car_oe})
        3'b100: begin
            o_AM = am_rom; o_PM = pm_rom; o_ETYP = etyp_rom; o_KSR = ksr_rom;
            o_MUL = mul_rom;
            o_KSL = ksl_rom;
            ar_muxed = ar_rom; dr_muxed = dr_rom; rr_muxed = rr_rom; o_SL = sl_rom; 
        end
        3'b010: begin
            o_AM = am_reg[0]; o_PM = pm_reg[0]; o_ETYP = etyp_reg[0]; o_KSR = ksr_reg[0];
            o_MUL = mul_reg[0];
            o_KSL = ksl_reg[0];
            ar_muxed = ar_reg[0]; dr_muxed = dr_reg[0]; rr_muxed = rr_reg[0]; o_SL = sl_reg[0]; 
        end
        3'b001: begin
            o_AM = am_reg[1]; o_PM = pm_reg[1]; o_ETYP = etyp_reg[1]; o_KSR = ksr_reg[1];
            o_MUL = mul_reg[1];
            o_KSL = ksl_reg[1];
            ar_muxed = ar_reg[1]; dr_muxed = dr_reg[1]; rr_muxed = rr_reg[1]; o_SL = sl_reg[1]; 
        end
        default: begin
            o_AM = `IB; o_PM = `IB; o_ETYP = `IB; o_KSR = `IB;
            o_MUL = {4{`IB}};
            o_KSL = {2{`IB}};
            ar_muxed = {4{`IB}}; dr_muxed = {4{`IB}}; rr_muxed = {4{`IB}}; o_SL = {4{`IB}}; 
        end
    endcase
end



///////////////////////////////////////////////////////////
//////  Test data serializer
////

reg     [16:0]  d0_testreg;
reg     [8:0]   d1_testreg;
assign  o_D[0] = d0_testreg[0];
assign  o_D[1] = d1_testreg[8];
always @(posedge emuclk) if(!phi1ncen_n) begin
    if(i_CYCLE_00) d0_testreg <= {i_REG_TEST_ATTNLV, i_REG_TEST_PHASE};
    else d0_testreg <= d0_testreg >> 1;

    if(i_CYCLE_00) d1_testreg <= i_REG_TEST_SNDDATA;
    else d1_testreg <= d1_testreg << 1;
end
 


endmodule

module IKAOPLL_rw_synchronizer #(parameter FULLY_SYNCHRONOUS = 1) (
    //chip clock
    input   wire            i_EMUCLK,
    input   wire            i_phiM_PCEN_n,
    input   wire            i_phi1_PCEN_n,
    input   wire            i_phi1_NCEN_n,

    input   wire            i_RST_n,

    input   wire            i_IN,
    output  wire            o_OUT
);

generate
if(FULLY_SYNCHRONOUS == 0) begin : FULLY_SYNCHRONOUS_0_busrq

wire            busrq_latched;
IKAOPLL_srlatch u_busrq_srlatch (
    .i_S((i_IN & i_RST_n) & ~o_OUT), .i_R(o_OUT | ~i_RST_n), .o_Q(busrq_latched)
);

reg     [2:0]   inreg;
assign          o_OUT = inreg[2];
always @(posedge i_EMUCLK) begin
    if(!i_RST_n) inreg <= 3'b000;
    else begin
        if(!i_phiM_PCEN_n) inreg[0] <= busrq_latched;
        if(!i_phi1_PCEN_n) inreg[1] <= inreg[0];
        if(!i_phi1_NCEN_n) inreg[2] <= inreg[1];
    end
end

end
else begin : FULLY_SYNCHRONOUS_1_busrq

reg     [2:0]   inreg;
assign          o_OUT = inreg[2];
always @(posedge i_EMUCLK) begin
    if(!i_RST_n) inreg <= 3'b000;
    else begin
        if(!i_phiM_PCEN_n) begin
            case({o_OUT, i_IN})
                2'b00: inreg[0] <= inreg[0];
                2'b01: inreg[0] <= 1'b1;
                2'b10: inreg[0] <= 1'b0;
                2'b11: inreg[0] <= 1'b0;
            endcase
        end
        if(!i_phi1_PCEN_n) inreg[1] <= inreg[0];
        if(!i_phi1_NCEN_n) inreg[2] <= inreg[1];
    end
end

end
endgenerate

endmodule

module IKAOPLL_d9reg #(parameter WIDTH = 1) (
    //chip clock
    input   wire                    i_EMUCLK,
    input   wire                    i_phi1_NCEN_n,

    input   wire                    i_EN,
    input   wire    [1:0]           i_TAPSEL,

    input   wire    [WIDTH-1:0]     i_D,
    output  reg     [WIDTH-1:0]     o_Q
);

wire    [WIDTH-1:0]     d, q_0, q_1, q_2, q_last;
IKAOPLL_sr #(.WIDTH(WIDTH), .LENGTH(9), .TAP0(2), .TAP1(5), .TAP2(8)) u_d9reg 
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(i_phi1_NCEN_n), .i_D(d), .o_Q_TAP0(q_0), .o_Q_TAP1(q_1), .o_Q_TAP2(q_2), .o_Q_LAST(q_last));

assign  d = i_EN ? i_D : q_last;

always @(*) begin
    case(i_TAPSEL)
        2'd0: o_Q = q_0;
        2'd1: o_Q = q_1;
        2'd2: o_Q = q_2;
        2'd3: o_Q = {WIDTH{1'b0}};
    endcase
end

endmodule

module IKAOPLL_instrom #(parameter INSTROM_STYLE = 0) (
    //chip clock
    input   wire            i_EMUCLK,
    input   wire            i_phi1_PCEN_n, //positive!

    input   wire    [1:0]   i_INST_BANK,
    input   wire    [3:0]   i_INST_ADDR,
    input   wire            i_BD0_SEL, i_HH_SEL, i_TT_SEL, i_BD1_SEL, i_SD_SEL, i_TC_SEL,
    input   wire            i_MnC_SEL, //1=MOD 0=CAR

    output  wire    [5:0]   o_TL_ROM,
    output  wire            o_DC_ROM, o_DM_ROM,
    output  wire    [2:0]   o_FB_ROM,
    output  wire            o_AM_ROM, o_PM_ROM, o_ETYP_ROM, o_KSR_ROM,
    output  wire    [3:0]   o_MUL_ROM,
    output  wire    [1:0]   o_KSL_ROM,
    output  wire    [3:0]   o_AR_ROM, o_DR_ROM, o_SL_ROM, o_RR_ROM
);


///////////////////////////////////////////////////////////
//////  Address decoder
////

wire            percussion_sel = |{i_BD0_SEL, i_HH_SEL, i_TT_SEL, i_BD1_SEL, i_SD_SEL, i_TC_SEL};
reg     [6:0]   mem_addr;

always @(*) begin
    if(percussion_sel) begin
        case({i_BD0_SEL, i_HH_SEL, i_TT_SEL, i_BD1_SEL, i_SD_SEL, i_TC_SEL})
            6'b100000: mem_addr = {i_INST_BANK, 1'b1, 4'h0};
            6'b010000: mem_addr = {i_INST_BANK, 1'b1, 4'h1};
            6'b001000: mem_addr = {i_INST_BANK, 1'b1, 4'h2};
            6'b000100: mem_addr = {i_INST_BANK, 1'b1, 4'h3};
            6'b000010: mem_addr = {i_INST_BANK, 1'b1, 4'h4};
            6'b000001: mem_addr = {i_INST_BANK, 1'b1, 4'h5};
            default:   mem_addr = {i_INST_BANK, 1'b1, 4'hF};
        endcase
    end
    else begin
        mem_addr = {i_INST_BANK, 1'b0, i_INST_ADDR};
    end
end



///////////////////////////////////////////////////////////
//////  Data section
////

/*
    implementation note:
    rom style 0: Store both instrument and percussion parameters in a single BRAM
    rom style 1: Store instrument in a BRAM, store percussion parameters in LUTs
    rom style 2: Store both instrument and percussion parameters in LUTs
*/

reg     [62:0]  mem_q;

generate

//
//  ROM STYLE 0: Store both instrument and percussion parameters in a single BRAM
//
if(INSTROM_STYLE == 0) begin
always @(posedge i_EMUCLK) if(!i_phi1_PCEN_n) begin
    case(mem_addr)
        //                         D D              KS             KS
        //                    TL   C M FB  AM PM ET  R    MUL       L      AR        DR        SL        RR
        //                                 MC MC MC MC <-M> <C-> M> <C <-M> <C-> <-M> <C-> <-M> <C-> <-M> <C->
        //YM2413 (OPLL) patches
        7'h00: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h01: mem_q <= 63'b011110_1_0_111_00_11_11_10_0001_0001_00_00_1110_0111_1111_1111_0000_0001_0000_0111;		//Violin
        7'h02: mem_q <= 63'b011010_0_1_101_00_01_00_10_0011_0001_00_00_1111_1111_1000_0111_0010_0001_0011_0011;		//Guitar
        7'h03: mem_q <= 63'b011001_0_0_000_00_00_00_10_0011_0001_10_00_1111_1100_0010_0100_0001_0010_0001_0011;		//Piano
        7'h04: mem_q <= 63'b001110_0_0_111_00_01_11_10_0001_0001_00_00_1001_0110_1000_0100_0111_0010_0000_0111;		//Flute
        7'h05: mem_q <= 63'b011110_0_0_110_00_00_11_00_0010_0001_00_00_1011_0111_1111_0110_0000_0010_0000_1000;		//Clarinet
        7'h06: mem_q <= 63'b010110_0_0_101_00_00_11_10_0001_0010_00_00_1110_0111_0000_0001_0000_0001_1111_1000;		//Oboe
        7'h07: mem_q <= 63'b011101_0_0_111_00_01_11_00_0001_0001_00_00_1000_1000_0010_1111_0001_0000_0000_0111;		//Trumpet
        7'h08: mem_q <= 63'b101101_1_0_100_00_00_11_00_0011_0001_00_00_1111_0111_1111_1111_0000_0000_0000_0111;		//Organ
        7'h09: mem_q <= 63'b011011_0_0_110_00_11_01_00_0001_0001_00_00_0110_0110_0100_0101_0001_0001_0000_0111;		//Horn
        7'h0A: mem_q <= 63'b001011_1_1_000_00_11_11_00_0001_0001_00_00_1000_1111_0101_1111_1000_0000_0001_0111;		//Synthesizer
        7'h0B: mem_q <= 63'b000011_1_0_001_00_00_00_10_0011_0001_10_00_1111_1110_1010_0100_0001_0000_0000_0100;		//Harpsichord
        7'h0C: mem_q <= 63'b100011_0_0_111_01_00_00_10_0111_0001_00_00_1111_1111_1000_1000_0010_0001_0010_0010;		//Vibraphone
        7'h0D: mem_q <= 63'b001100_0_0_101_00_11_10_01_0001_0000_00_00_1111_1111_0010_0101_0010_0100_1001_0010;		//Synthesizer Bass
        7'h0E: mem_q <= 63'b010100_0_0_011_00_00_00_00_0001_0001_01_00_1100_1001_0011_0010_0000_0000_0011_0010;		//Acoustic Bass
        7'h0F: mem_q <= 63'b001001_0_0_011_00_11_00_00_0001_0001_10_00_1111_1110_0001_0101_0001_0001_0001_0011;		//Electric Guitar

        7'h10: mem_q <= 63'b011000_0_1_111_00_00_00_00_0001_0000_00_00_1101_0000_1111_0000_0110_0000_1010_0000;		//bass drum 0
        7'h11: mem_q <= 63'b000000_0_0_000_00_00_00_00_0001_0000_00_00_1100_0000_1000_0000_1010_0000_0111_0000;		//hi hat     
        7'h12: mem_q <= 63'b000000_0_0_000_00_00_00_00_0101_0000_00_00_1111_0000_1000_0000_0101_0000_1001_0000;		//tom tom    
        7'h13: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1111_0000_1000_0000_0110_0000_1101;		//bass drum 1
        7'h14: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1101_0000_1000_0000_0100_0000_1000;		//snare drum 
        7'h15: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1010_0000_1010_0000_0101_0000_0101;		//top cymbal 
        7'h16: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h17: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h18: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h19: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h1A: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h1B: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h1C: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h1D: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h1E: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h1F: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;

        //YM2423 (OPLL-X) patches
        7'h20: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h21: mem_q <= 63'b011011_0_0_111_00_11_11_00_0001_0001_00_00_1001_0101_0100_1111_0001_0000_0000_0110;		//1	Strings	Saw wave with vibrato Violin
        7'h22: mem_q <= 63'b010001_0_0_100_11_00_01_11_0011_0001_01_00_1111_1111_0011_0010_0111_1111_0000_1011;		//2	Guitar	Jazz GuitarPiano
        7'h23: mem_q <= 63'b010001_0_0_101_00_10_01_00_0001_0001_00_10_1111_1111_0010_0010_0111_0111_0000_0101;		//3	Electric Guitar	Same as OPLL No.15 Synth 
        7'h24: mem_q <= 63'b101000_0_0_111_11_00_01_11_0011_0010_00_00_1111_1111_0011_0010_0111_1011_0000_0100;		//4	Electric Piano 2	Slow attack, tremoloDing-a-ling
        7'h25: mem_q <= 63'b010111_0_0_101_00_10_11_11_0010_0001_10_00_0101_0110_0001_1111_0110_0000_0000_1001;		//5 	Flute	Same as OPLL No.4Clarinet
        7'h26: mem_q <= 63'b011000_0_0_110_00_00_01_11_0011_0000_00_00_1111_1111_0111_0100_0101_1000_0000_0101;		//6	Marimba 	Also be used as steel drumXyophone
        7'h27: mem_q <= 63'b011100_0_0_111_00_10_01_11_0001_0001_00_00_0101_0111_0001_0001_0010_0010_0000_0110;		//7	Trumpet 	Same as OPLL No.7Trumpet
        7'h28: mem_q <= 63'b011011_0_0_111_01_11_01_01_0001_0100_00_00_0111_0011_0100_0100_0000_0000_0000_0110;		//8	Harmonica Harmonica synth
        7'h29: mem_q <= 63'b001101_0_0_011_00_10_01_11_0000_0000_01_00_0100_0110_0010_0101_0010_0000_0000_0110;		//9	Tuba Tuba
        7'h2A: mem_q <= 63'b010000_0_0_101_00_10_01_00_0000_0000_00_10_1111_1111_0011_0101_0010_0000_0000_0100;		//10 	Synth Brass 2 Synth sweep
        7'h2B: mem_q <= 63'b011011_0_0_111_00_11_11_00_0001_0001_00_00_1100_1001_0101_0110_1111_1111_0011_0110;		//11 	Short Saw	Saw wave with short envelopeSynth hit
        7'h2C: mem_q <= 63'b011100_0_0_000_11_11_11_11_1001_0001_11_00_1111_1111_0101_0011_0111_1111_0111_0010;		//12 	Vibraphone	Bright vibraphoneVibes
        7'h2D: mem_q <= 63'b010001_0_0_011_01_10_11_00_0000_0010_10_00_1001_1100_0100_0001_1111_1111_0111_0111;		//13 	Electric Guitar 2	Clean guitar with feedbackHarmonic bass
        7'h2E: mem_q <= 63'b010111_0_0_110_00_00_11_11_0000_0000_00_00_1111_1111_0011_0001_1011_1111_0111_1100;		//14 	Synth Bass 2Snappy bass
        7'h2F: mem_q <= 63'b001101_0_0_101_00_00_11_11_0001_0110_00_00_1111_1111_0010_0100_0010_1001_0111_1100;		//15 	Sitar	Also be used as ShamisenBanjo

        7'h30: mem_q <= 63'b011000_0_1_111_00_00_00_00_0001_0000_00_00_1101_0000_1111_0000_0110_0000_1010_0000;		//bass drum 0
        7'h31: mem_q <= 63'b000000_0_0_000_00_00_00_00_0001_0000_00_00_1100_0000_1000_0000_1010_0000_0111_0000;		//hi hat     
        7'h32: mem_q <= 63'b000000_0_0_000_00_00_00_00_0101_0000_00_00_1111_0000_1000_0000_0101_0000_1001_0000;		//tom tom    
        7'h33: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1111_0000_1000_0000_0110_0000_1101;		//bass drum 1
        7'h34: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1101_0000_1000_0000_0100_0000_1000;		//snare drum 
        7'h35: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1010_0000_1010_0000_0101_0000_0101;		//top cymbal 
        7'h36: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h37: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h38: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h39: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h3A: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h3B: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h3C: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h3D: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h3E: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h3F: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;

        //YMF281 (OPLL-P) patches
        7'h40: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h41: mem_q <= 63'b011010_0_0_111_00_10_11_10_0010_0001_00_00_1111_0110_0110_0100_0000_0001_0001_0110;		// Clarinet ~~ Electric String 	Square wave with vibrato
        7'h42: mem_q <= 63'b000101_0_0_000_00_00_00_01_0000_0000_01_00_1111_1000_0110_0011_0111_0110_0011_0011;		// Synth Bass ~~ Bow wow 	Triangular wave
        7'h43: mem_q <= 63'b010110_0_0_000_00_00_00_10_0011_0001_10_00_1111_1111_0001_0100_0011_0010_0001_0011;		// Piano ~~ Electric Guitar 	Despite of its name, same as Piano of YM2413.
        7'h44: mem_q <= 63'b001011_0_1_111_00_10_11_10_0001_0001_00_00_1111_0110_1001_0100_0111_0001_0000_0111;		// Flute ~~ Organ 	Sine wave 
        7'h45: mem_q <= 63'b011110_0_0_110_00_00_01_00_0010_0001_00_00_1111_0111_1001_0110_0000_0010_0000_1000;		// Square Wave ~~ Clarinet 	Same as ones of YM2413. 
        7'h46: mem_q <= 63'b000010_0_1_110_00_01_01_00_0000_0001_10_00_1111_0110_1001_0001_0010_0010_0000_0111;		// Space Oboe ~~ Saxophone 	Saw wave with vibrato 
        7'h47: mem_q <= 63'b011011_0_0_111_00_01_11_00_0001_0001_00_00_1000_1000_0100_1111_0001_0000_0000_0111;		// Trumpet ~~ Trumpet 	Same as ones of YM2413. 
        7'h48: mem_q <= 63'b001010_0_0_010_00_00_11_11_0111_0010_11_00_0110_0110_0110_0100_0100_0010_0111_1001;		// Wow Bell ~~ Street Organ 	Calliope 
        7'h49: mem_q <= 63'b000111_0_0_011_00_11_00_00_0001_0001_00_00_1111_0111_0101_0000_0101_1111_0001_0101;		// Electric Guitar ~~ Synth Brass 	Same as Synthesizer of YM2413. 
        7'h4A: mem_q <= 63'b011110_0_0_111_00_00_10_10_0110_0001_01_00_1111_1111_0010_0011_1111_1111_0111_0111;		// Vibes ~~ Electric Piano 	Simulate of Rhodes Piano 
        7'h4B: mem_q <= 63'b011000_0_0_110_00_00_00_00_0000_0000_00_00_1100_1111_0101_0011_0010_1111_0000_0010;		// Bass ~~ Bass 	Electric bass 
        7'h4C: mem_q <= 63'b100101_0_0_111_01_00_00_10_0111_0001_00_00_1111_1111_0111_0011_0010_1111_0001_0111;		// Vibraphone ~~ Vibraphone	Same as ones of YM2413.
        7'h4D: mem_q <= 63'b000000_0_0_000_00_01_11_10_0101_0100_00_00_1111_1111_1111_0011_0111_1111_0111_0101;		// Vibrato Bell ~~ Chime 	Bell 
        7'h4E: mem_q <= 63'b000000_0_0_111_00_00_01_11_0001_0001_00_00_1101_1111_1101_0011_1111_1111_1111_1011;		// Click Sine ~~ Tom Tom II 	Tom 
        7'h4F: mem_q <= 63'b000000_0_0_111_00_00_11_10_1010_0001_00_00_1001_1000_0101_0100_0000_1111_1111_0101;		// Noise and Tone ~~ Noise 	for S.E. 

        7'h50: mem_q <= 63'b011000_0_1_111_00_00_00_00_0001_0000_00_00_1101_0000_1111_0000_0110_0000_1010_0000;		//bass drum 0
        7'h51: mem_q <= 63'b000000_0_0_000_00_00_00_00_0001_0000_00_00_1100_0000_1000_0000_1010_0000_0111_0000;		//hi hat     
        7'h52: mem_q <= 63'b000000_0_0_000_00_00_00_00_0101_0000_00_00_1111_0000_1000_0000_0101_0000_1001_0000;		//tom tom    
        7'h53: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1111_0000_1000_0000_0110_0000_1101;		//bass drum 1
        7'h54: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1101_0000_1000_0000_0100_0000_1000;		//snare drum 
        7'h55: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1010_0000_1010_0000_0101_0000_0101;		//top cymbal 
        7'h56: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h57: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h58: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h59: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h5A: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h5B: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h5C: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h5D: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h5E: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h5F: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;

        //VRC7 patches
        7'h60: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h61: mem_q <= 63'b000101_0_0_110_00_00_01_00_0011_0001_00_00_1100_1000_1000_0001_0100_0010_0010_0111;		// Buzzy Bell
        7'h62: mem_q <= 63'b010100_0_1_101_00_01_00_10_0011_0001_00_00_1111_1111_1000_0111_0010_0001_0011_0010;		// Guitar
        7'h63: mem_q <= 63'b001000_0_1_000_00_00_10_11_0001_0001_00_00_1111_1100_1010_0010_0010_0010_1000_0010;		// Wurly
        7'h64: mem_q <= 63'b001100_0_0_111_00_01_11_10_0001_0001_00_00_1111_0110_1000_0100_0110_0010_0000_0111;		// Flute
        7'h65: mem_q <= 63'b011110_0_0_110_00_00_11_00_0010_0001_00_00_1111_0111_1111_0110_0000_0010_0000_1000;		// Clarinet
        7'h66: mem_q <= 63'b000101_0_0_000_00_00_00_00_0010_0001_00_00_1010_1111_1100_0010_0000_0000_0011_0010;		// Synth
        7'h67: mem_q <= 63'b011101_0_0_111_00_01_11_00_0001_0001_00_00_1000_1000_0010_1111_0001_0000_0000_0111;		// Trumpet
        7'h68: mem_q <= 63'b100010_1_0_111_00_00_11_00_0011_0001_00_00_1111_0111_1111_0011_0000_0001_0000_0111;		// Organ
        7'h69: mem_q <= 63'b100101_0_0_000_00_00_00_11_0101_0001_00_00_0100_0111_0001_0001_0000_1111_0000_0001;		// Bells
        7'h6A: mem_q <= 63'b010000_0_1_111_10_00_00_10_0101_0001_00_00_1011_1010_1000_1010_0101_0000_0000_0010;		// Vibes
        7'h6B: mem_q <= 63'b011110_0_0_111_01_01_00_10_0111_0001_01_00_1111_1111_1010_1000_0010_0001_0010_0010;		// Vibraphone
        7'h6C: mem_q <= 63'b010001_0_0_110_00_10_11_10_0001_0011_00_00_0110_0111_0101_0100_0001_0001_0000_0110;		// Tutti
        7'h6D: mem_q <= 63'b010011_0_0_101_00_00_00_00_0001_0010_11_00_1111_1001_0011_0010_1000_1111_0011_0010;		// Fretless
        7'h6E: mem_q <= 63'b001100_0_0_000_00_11_11_00_0001_0011_00_00_1010_1111_0100_1111_0011_0000_0000_0110;		// Synth Bass
        7'h6F: mem_q <= 63'b001101_0_0_000_00_01_11_00_0001_0010_00_00_1010_1111_0001_1111_0101_0000_0000_1000;		// Sweep

        7'h70: mem_q <= 63'b011000_0_1_111_00_00_00_00_0001_0000_00_00_1101_0000_1111_0000_0110_0000_1010_0000;		//bass drum 0
        7'h71: mem_q <= 63'b000000_0_0_000_00_00_00_00_0001_0000_00_00_1100_0000_1000_0000_1010_0000_0111_0000;		//hi hat     
        7'h72: mem_q <= 63'b000000_0_0_000_00_00_00_00_0101_0000_00_00_1111_0000_1000_0000_0101_0000_1001_0000;		//tom tom    
        7'h73: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1111_0000_1000_0000_0110_0000_1101;		//bass drum 1
        7'h74: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1101_0000_1000_0000_0100_0000_1000;		//snare drum 
        7'h75: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1010_0000_1010_0000_0101_0000_0101;		//top cymbal 
        7'h76: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h77: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h78: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h79: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h7A: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h7B: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h7C: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h7D: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h7E: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h7F: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
    endcase
end
end


//
//  ROM STYLE 1: Store instrument in a BRAM, store percussion parameters in LUTs
//
else if(INSTROM_STYLE == 1) begin

reg     [62:0]  inst_q;
reg     [62:0]  perc_q;

reg             ipsel; //instrument/percussion select
always @(posedge i_EMUCLK) if(!i_phi1_PCEN_n) ipsel <= mem_addr[4]; //delay address bit to select data properly
always @(*) mem_q = ipsel ? perc_q : inst_q;

always @(posedge i_EMUCLK) if(!i_phi1_PCEN_n) begin

    //BLOCK RAM REGION
    case({mem_addr[6:5], mem_addr[3:0]})
        //                         D D              KS             KS
        //                    TL   C M FB  AM PM ET  R    MUL       L      AR        DR        SL        RR
        //                                 MC MC MC MC <-M> <C-> M> <C <-M> <C-> <-M> <C-> <-M> <C-> <-M> <C->
        //YM2413 (OPLL) patches
        6'h00: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        6'h01: mem_q <= 63'b011110_1_0_111_00_11_11_10_0001_0001_00_00_1110_0111_1111_1111_0000_0001_0000_0111;		//Violin
        6'h02: mem_q <= 63'b011010_0_1_101_00_01_00_10_0011_0001_00_00_1111_1111_1000_0111_0010_0001_0011_0011;		//Guitar
        6'h03: mem_q <= 63'b011001_0_0_000_00_00_00_10_0011_0001_10_00_1111_1100_0010_0100_0001_0010_0001_0011;		//Piano
        6'h04: mem_q <= 63'b001110_0_0_111_00_01_11_10_0001_0001_00_00_1001_0110_1000_0100_0111_0010_0000_0111;		//Flute
        6'h05: mem_q <= 63'b011110_0_0_110_00_00_11_00_0010_0001_00_00_1011_0111_1111_0110_0000_0010_0000_1000;		//Clarinet
        6'h06: mem_q <= 63'b010110_0_0_101_00_00_11_10_0001_0010_00_00_1110_0111_0000_0001_0000_0001_1111_1000;		//Oboe
        6'h07: mem_q <= 63'b011101_0_0_111_00_01_11_00_0001_0001_00_00_1000_1000_0010_1111_0001_0000_0000_0111;		//Trumpet
        6'h08: mem_q <= 63'b101101_1_0_100_00_00_11_00_0011_0001_00_00_1111_0111_1111_1111_0000_0000_0000_0111;		//Organ
        6'h09: mem_q <= 63'b011011_0_0_110_00_11_01_00_0001_0001_00_00_0110_0110_0100_0101_0001_0001_0000_0111;		//Horn
        6'h0A: mem_q <= 63'b001011_1_1_000_00_11_11_00_0001_0001_00_00_1000_1111_0101_1111_1000_0000_0001_0111;		//Synthesizer
        6'h0B: mem_q <= 63'b000011_1_0_001_00_00_00_10_0011_0001_10_00_1111_1110_1010_0100_0001_0000_0000_0100;		//Harpsichord
        6'h0C: mem_q <= 63'b100011_0_0_111_01_00_00_10_0111_0001_00_00_1111_1111_1000_1000_0010_0001_0010_0010;		//Vibraphone
        6'h0D: mem_q <= 63'b001100_0_0_101_00_11_10_01_0001_0000_00_00_1111_1111_0010_0101_0010_0100_1001_0010;		//Synthesizer Bass
        6'h0E: mem_q <= 63'b010100_0_0_011_00_00_00_00_0001_0001_01_00_1100_1001_0011_0010_0000_0000_0011_0010;		//Acoustic Bass
        6'h0F: mem_q <= 63'b001001_0_0_011_00_11_00_00_0001_0001_10_00_1111_1110_0001_0101_0001_0001_0001_0011;		//Electric Guitar

        //YM2423 (OPLL-X) patches
        6'h10: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        6'h11: mem_q <= 63'b011011_0_0_111_00_11_11_00_0001_0001_00_00_1001_0101_0100_1111_0001_0000_0000_0110;		//1	Strings	Saw wave with vibrato Violin
        6'h12: mem_q <= 63'b010001_0_0_100_11_00_01_11_0011_0001_01_00_1111_1111_0011_0010_0111_1111_0000_1011;		//2	Guitar	Jazz GuitarPiano
        6'h13: mem_q <= 63'b010001_0_0_101_00_10_01_00_0001_0001_00_10_1111_1111_0010_0010_0111_0111_0000_0101;		//3	Electric Guitar	Same as OPLL No.15 Synth 
        6'h14: mem_q <= 63'b101000_0_0_111_11_00_01_11_0011_0010_00_00_1111_1111_0011_0010_0111_1011_0000_0100;		//4	Electric Piano 2	Slow attack, tremoloDing-a-ling
        6'h15: mem_q <= 63'b010111_0_0_101_00_10_11_11_0010_0001_10_00_0101_0110_0001_1111_0110_0000_0000_1001;		//5 	Flute	Same as OPLL No.4Clarinet
        6'h16: mem_q <= 63'b011000_0_0_110_00_00_01_11_0011_0000_00_00_1111_1111_0111_0100_0101_1000_0000_0101;		//6	Marimba 	Also be used as steel drumXyophone
        6'h17: mem_q <= 63'b011100_0_0_111_00_10_01_11_0001_0001_00_00_0101_0111_0001_0001_0010_0010_0000_0110;		//7	Trumpet 	Same as OPLL No.7Trumpet
        6'h18: mem_q <= 63'b011011_0_0_111_01_11_01_01_0001_0100_00_00_0111_0011_0100_0100_0000_0000_0000_0110;		//8	Harmonica Harmonica synth
        6'h19: mem_q <= 63'b001101_0_0_011_00_10_01_11_0000_0000_01_00_0100_0110_0010_0101_0010_0000_0000_0110;		//9	Tuba Tuba
        6'h1A: mem_q <= 63'b010000_0_0_101_00_10_01_00_0000_0000_00_10_1111_1111_0011_0101_0010_0000_0000_0100;		//10 	Synth Brass 2 Synth sweep
        6'h1B: mem_q <= 63'b011011_0_0_111_00_11_11_00_0001_0001_00_00_1100_1001_0101_0110_1111_1111_0011_0110;		//11 	Short Saw	Saw wave with short envelopeSynth hit
        6'h1C: mem_q <= 63'b011100_0_0_000_11_11_11_11_1001_0001_11_00_1111_1111_0101_0011_0111_1111_0111_0010;		//12 	Vibraphone	Bright vibraphoneVibes
        6'h1D: mem_q <= 63'b010001_0_0_011_01_10_11_00_0000_0010_10_00_1001_1100_0100_0001_1111_1111_0111_0111;		//13 	Electric Guitar 2	Clean guitar with feedbackHarmonic bass
        6'h1E: mem_q <= 63'b010111_0_0_110_00_00_11_11_0000_0000_00_00_1111_1111_0011_0001_1011_1111_0111_1100;		//14 	Synth Bass 2Snappy bass
        6'h1F: mem_q <= 63'b001101_0_0_101_00_00_11_11_0001_0110_00_00_1111_1111_0010_0100_0010_1001_0111_1100;		//15 	Sitar	Also be used as ShamisenBanjo

        //YMF281 (OPLL-P) patches
        6'h20: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        6'h21: mem_q <= 63'b011010_0_0_111_00_10_11_10_0010_0001_00_00_1111_0110_0110_0100_0000_0001_0001_0110;		// Clarinet ~~ Electric String 	Square wave with vibrato
        6'h22: mem_q <= 63'b000101_0_0_000_00_00_00_01_0000_0000_01_00_1111_1000_0110_0011_0111_0110_0011_0011;		// Synth Bass ~~ Bow wow 	Triangular wave
        6'h23: mem_q <= 63'b010110_0_0_000_00_00_00_10_0011_0001_10_00_1111_1111_0001_0100_0011_0010_0001_0011;		// Piano ~~ Electric Guitar 	Despite of its name, same as Piano of YM2413.
        6'h24: mem_q <= 63'b001011_0_1_111_00_10_11_10_0001_0001_00_00_1111_0110_1001_0100_0111_0001_0000_0111;		// Flute ~~ Organ 	Sine wave 
        6'h25: mem_q <= 63'b011110_0_0_110_00_00_01_00_0010_0001_00_00_1111_0111_1001_0110_0000_0010_0000_1000;		// Square Wave ~~ Clarinet 	Same as ones of YM2413. 
        6'h26: mem_q <= 63'b000010_0_1_110_00_01_01_00_0000_0001_10_00_1111_0110_1001_0001_0010_0010_0000_0111;		// Space Oboe ~~ Saxophone 	Saw wave with vibrato 
        6'h27: mem_q <= 63'b011011_0_0_111_00_01_11_00_0001_0001_00_00_1000_1000_0100_1111_0001_0000_0000_0111;		// Trumpet ~~ Trumpet 	Same as ones of YM2413. 
        6'h28: mem_q <= 63'b001010_0_0_010_00_00_11_11_0111_0010_11_00_0110_0110_0110_0100_0100_0010_0111_1001;		// Wow Bell ~~ Street Organ 	Calliope 
        6'h29: mem_q <= 63'b000111_0_0_011_00_11_00_00_0001_0001_00_00_1111_0111_0101_0000_0101_1111_0001_0101;		// Electric Guitar ~~ Synth Brass 	Same as Synthesizer of YM2413. 
        6'h2A: mem_q <= 63'b011110_0_0_111_00_00_10_10_0110_0001_01_00_1111_1111_0010_0011_1111_1111_0111_0111;		// Vibes ~~ Electric Piano 	Simulate of Rhodes Piano 
        6'h2B: mem_q <= 63'b011000_0_0_110_00_00_00_00_0000_0000_00_00_1100_1111_0101_0011_0010_1111_0000_0010;		// Bass ~~ Bass 	Electric bass 
        6'h2C: mem_q <= 63'b100101_0_0_111_01_00_00_10_0111_0001_00_00_1111_1111_0111_0011_0010_1111_0001_0111;		// Vibraphone ~~ Vibraphone	Same as ones of YM2413.
        6'h2D: mem_q <= 63'b000000_0_0_000_00_01_11_10_0101_0100_00_00_1111_1111_1111_0011_0111_1111_0111_0101;		// Vibrato Bell ~~ Chime 	Bell 
        6'h2E: mem_q <= 63'b000000_0_0_111_00_00_01_11_0001_0001_00_00_1101_1111_1101_0011_1111_1111_1111_1011;		// Click Sine ~~ Tom Tom II 	Tom 
        6'h2F: mem_q <= 63'b000000_0_0_111_00_00_11_10_1010_0001_00_00_1001_1000_0101_0100_0000_1111_1111_0101;		// Noise and Tone ~~ Noise 	for S.E. 

        //VRC7 patches
        6'h30: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        6'h31: mem_q <= 63'b000101_0_0_110_00_00_01_00_0011_0001_00_00_1100_1000_1000_0001_0100_0010_0010_0111;		// Buzzy Bell
        6'h32: mem_q <= 63'b010100_0_1_101_00_01_00_10_0011_0001_00_00_1111_1111_1000_0111_0010_0001_0011_0010;		// Guitar
        6'h33: mem_q <= 63'b001000_0_1_000_00_00_10_11_0001_0001_00_00_1111_1100_1010_0010_0010_0010_1000_0010;		// Wurly
        6'h34: mem_q <= 63'b001100_0_0_111_00_01_11_10_0001_0001_00_00_1111_0110_1000_0100_0110_0010_0000_0111;		// Flute
        6'h35: mem_q <= 63'b011110_0_0_110_00_00_11_00_0010_0001_00_00_1111_0111_1111_0110_0000_0010_0000_1000;		// Clarinet
        6'h36: mem_q <= 63'b000101_0_0_000_00_00_00_00_0010_0001_00_00_1010_1111_1100_0010_0000_0000_0011_0010;		// Synth
        6'h37: mem_q <= 63'b011101_0_0_111_00_01_11_00_0001_0001_00_00_1000_1000_0010_1111_0001_0000_0000_0111;		// Trumpet
        6'h38: mem_q <= 63'b100010_1_0_111_00_00_11_00_0011_0001_00_00_1111_0111_1111_0011_0000_0001_0000_0111;		// Organ
        6'h39: mem_q <= 63'b100101_0_0_000_00_00_00_11_0101_0001_00_00_0100_0111_0001_0001_0000_1111_0000_0001;		// Bells
        6'h3A: mem_q <= 63'b010000_0_1_111_10_00_00_10_0101_0001_00_00_1011_1010_1000_1010_0101_0000_0000_0010;		// Vibes
        6'h3B: mem_q <= 63'b011110_0_0_111_01_01_00_10_0111_0001_01_00_1111_1111_1010_1000_0010_0001_0010_0010;		// Vibraphone
        6'h3C: mem_q <= 63'b010001_0_0_110_00_10_11_10_0001_0011_00_00_0110_0111_0101_0100_0001_0001_0000_0110;		// Tutti
        6'h3D: mem_q <= 63'b010011_0_0_101_00_00_00_00_0001_0010_11_00_1111_1001_0011_0010_1000_1111_0011_0010;		// Fretless
        6'h3E: mem_q <= 63'b001100_0_0_000_00_11_11_00_0001_0011_00_00_1010_1111_0100_1111_0011_0000_0000_0110;		// Synth Bass
        6'h3F: mem_q <= 63'b001101_0_0_000_00_01_11_00_0001_0010_00_00_1010_1111_0001_1111_0101_0000_0000_1000;		// Sweep
    endcase

    //LUT REGION
    case(mem_addr[2:0])
        3'h0:  perc_q <= 63'b011000_0_1_111_00_00_00_00_0001_0000_00_00_1101_0000_1111_0000_0110_0000_1010_0000; //bass drum 0
        3'h1:  perc_q <= 63'b000000_0_0_000_00_00_00_00_0001_0000_00_00_1100_0000_1000_0000_1010_0000_0111_0000; //hi hat     
        3'h2:  perc_q <= 63'b000000_0_0_000_00_00_00_00_0101_0000_00_00_1111_0000_1000_0000_0101_0000_1001_0000; //tom tom    
        3'h3:  perc_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1111_0000_1000_0000_0110_0000_1101; //bass drum 1
        3'h4:  perc_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1101_0000_1000_0000_0100_0000_1000; //snare drum 
        3'h5:  perc_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1010_0000_1010_0000_0101_0000_0101; //top cymbal 
        default: perc_q <= 63'b000000_0_0_000_00_00_00_00_00000000_0000_0000_0000_0000_0000_0000_0000_0000_0000;  
    endcase
end
end

//
//  ROM STYLE 2: Store both instrument and percussion parameters in LUTs
//
else if(INSTROM_STYLE == 2) begin
always @(posedge i_EMUCLK) if(!i_phi1_PCEN_n) begin
    case(mem_addr)
        //                         D D              KS           KS
        //                    TL   C M FB  AM PM ET  R   MUL      L     AR       DR       SL       RR
        //                                 MC MC MC MC <-M><C-> M><C <-M><C-> <-M><C-> <-M><C-> <-M><C->
        //YM2413 (OPLL) patches
        7'h00: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h01: mem_q <= 63'b011110_1_0_111_00_11_11_10_0001_0001_00_00_1110_0111_1111_1111_0000_0001_0000_0111;		//Violin
        7'h02: mem_q <= 63'b011010_0_1_101_00_01_00_10_0011_0001_00_00_1111_1111_1000_0111_0010_0001_0011_0011;		//Guitar
        7'h03: mem_q <= 63'b011001_0_0_000_00_00_00_10_0011_0001_10_00_1111_1100_0010_0100_0001_0010_0001_0011;		//Piano
        7'h04: mem_q <= 63'b001110_0_0_111_00_01_11_10_0001_0001_00_00_1001_0110_1000_0100_0111_0010_0000_0111;		//Flute
        7'h05: mem_q <= 63'b011110_0_0_110_00_00_11_00_0010_0001_00_00_1011_0111_1111_0110_0000_0010_0000_1000;		//Clarinet
        7'h06: mem_q <= 63'b010110_0_0_101_00_00_11_10_0001_0010_00_00_1110_0111_0000_0001_0000_0001_1111_1000;		//Oboe
        7'h07: mem_q <= 63'b011101_0_0_111_00_01_11_00_0001_0001_00_00_1000_1000_0010_1111_0001_0000_0000_0111;		//Trumpet
        7'h08: mem_q <= 63'b101101_1_0_100_00_00_11_00_0011_0001_00_00_1111_0111_1111_1111_0000_0000_0000_0111;		//Organ
        7'h09: mem_q <= 63'b011011_0_0_110_00_11_01_00_0001_0001_00_00_0110_0110_0100_0101_0001_0001_0000_0111;		//Horn
        7'h0A: mem_q <= 63'b001011_1_1_000_00_11_11_00_0001_0001_00_00_1000_1111_0101_1111_1000_0000_0001_0111;		//Synthesizer
        7'h0B: mem_q <= 63'b000011_1_0_001_00_00_00_10_0011_0001_10_00_1111_1110_1010_0100_0001_0000_0000_0100;		//Harpsichord
        7'h0C: mem_q <= 63'b100011_0_0_111_01_00_00_10_0111_0001_00_00_1111_1111_1000_1000_0010_0001_0010_0010;		//Vibraphone
        7'h0D: mem_q <= 63'b001100_0_0_101_00_11_10_01_0001_0000_00_00_1111_1111_0010_0101_0010_0100_1001_0010;		//Synthesizer Bass
        7'h0E: mem_q <= 63'b010100_0_0_011_00_00_00_00_0001_0001_01_00_1100_1001_0011_0010_0000_0000_0011_0010;		//Acoustic Bass
        7'h0F: mem_q <= 63'b001001_0_0_011_00_11_00_00_0001_0001_10_00_1111_1110_0001_0101_0001_0001_0001_0011;		//Electric Guitar

        7'h10: mem_q <= 63'b011000_0_1_111_00_00_00_00_0001_0000_00_00_1101_0000_1111_0000_0110_0000_1010_0000;		//bass drum 0
        7'h11: mem_q <= 63'b000000_0_0_000_00_00_00_00_0001_0000_00_00_1100_0000_1000_0000_1010_0000_0111_0000;		//hi hat     
        7'h12: mem_q <= 63'b000000_0_0_000_00_00_00_00_0101_0000_00_00_1111_0000_1000_0000_0101_0000_1001_0000;		//tom tom    
        7'h13: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1111_0000_1000_0000_0110_0000_1101;		//bass drum 1
        7'h14: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1101_0000_1000_0000_0100_0000_1000;		//snare drum 
        7'h15: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1010_0000_1010_0000_0101_0000_0101;		//top cymbal 

        //YM2423 (OPLL-X) patches
        7'h20: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h21: mem_q <= 63'b011011_0_0_111_00_11_11_00_0001_0001_00_00_1001_0101_0100_1111_0001_0000_0000_0110;		//1	Strings	Saw wave with vibrato Violin
        7'h22: mem_q <= 63'b010001_0_0_100_11_00_01_11_0011_0001_01_00_1111_1111_0011_0010_0111_1111_0000_1011;		//2	Guitar	Jazz GuitarPiano
        7'h23: mem_q <= 63'b010001_0_0_101_00_10_01_00_0001_0001_00_10_1111_1111_0010_0010_0111_0111_0000_0101;		//3	Electric Guitar	Same as OPLL No.15 Synth 
        7'h24: mem_q <= 63'b101000_0_0_111_11_00_01_11_0011_0010_00_00_1111_1111_0011_0010_0111_1011_0000_0100;		//4	Electric Piano 2	Slow attack, tremoloDing-a-ling
        7'h25: mem_q <= 63'b010111_0_0_101_00_10_11_11_0010_0001_10_00_0101_0110_0001_1111_0110_0000_0000_1001;		//5 	Flute	Same as OPLL No.4Clarinet
        7'h26: mem_q <= 63'b011000_0_0_110_00_00_01_11_0011_0000_00_00_1111_1111_0111_0100_0101_1000_0000_0101;		//6	Marimba 	Also be used as steel drumXyophone
        7'h27: mem_q <= 63'b011100_0_0_111_00_10_01_11_0001_0001_00_00_0101_0111_0001_0001_0010_0010_0000_0110;		//7	Trumpet 	Same as OPLL No.7Trumpet
        7'h28: mem_q <= 63'b011011_0_0_111_01_11_01_01_0001_0100_00_00_0111_0011_0100_0100_0000_0000_0000_0110;		//8	Harmonica Harmonica synth
        7'h29: mem_q <= 63'b001101_0_0_011_00_10_01_11_0000_0000_01_00_0100_0110_0010_0101_0010_0000_0000_0110;		//9	Tuba Tuba
        7'h2A: mem_q <= 63'b010000_0_0_101_00_10_01_00_0000_0000_00_10_1111_1111_0011_0101_0010_0000_0000_0100;		//10 	Synth Brass 2 Synth sweep
        7'h2B: mem_q <= 63'b011011_0_0_111_00_11_11_00_0001_0001_00_00_1100_1001_0101_0110_1111_1111_0011_0110;		//11 	Short Saw	Saw wave with short envelopeSynth hit
        7'h2C: mem_q <= 63'b011100_0_0_000_11_11_11_11_1001_0001_11_00_1111_1111_0101_0011_0111_1111_0111_0010;		//12 	Vibraphone	Bright vibraphoneVibes
        7'h2D: mem_q <= 63'b010001_0_0_011_01_10_11_00_0000_0010_10_00_1001_1100_0100_0001_1111_1111_0111_0111;		//13 	Electric Guitar 2	Clean guitar with feedbackHarmonic bass
        7'h2E: mem_q <= 63'b010111_0_0_110_00_00_11_11_0000_0000_00_00_1111_1111_0011_0001_1011_1111_0111_1100;		//14 	Synth Bass 2Snappy bass
        7'h2F: mem_q <= 63'b001101_0_0_101_00_00_11_11_0001_0110_00_00_1111_1111_0010_0100_0010_1001_0111_1100;		//15 	Sitar	Also be used as ShamisenBanjo

        7'h30: mem_q <= 63'b011000_0_1_111_00_00_00_00_0001_0000_00_00_1101_0000_1111_0000_0110_0000_1010_0000;		//bass drum 0
        7'h31: mem_q <= 63'b000000_0_0_000_00_00_00_00_0001_0000_00_00_1100_0000_1000_0000_1010_0000_0111_0000;		//hi hat     
        7'h32: mem_q <= 63'b000000_0_0_000_00_00_00_00_0101_0000_00_00_1111_0000_1000_0000_0101_0000_1001_0000;		//tom tom    
        7'h33: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1111_0000_1000_0000_0110_0000_1101;		//bass drum 1
        7'h34: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1101_0000_1000_0000_0100_0000_1000;		//snare drum 
        7'h35: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1010_0000_1010_0000_0101_0000_0101;		//top cymbal 

        //YMF281 (OPLL-P) patches
        7'h40: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h41: mem_q <= 63'b011010_0_0_111_00_10_11_10_0010_0001_00_00_1111_0110_0110_0100_0000_0001_0001_0110;		// Clarinet ~~ Electric String 	Square wave with vibrato
        7'h42: mem_q <= 63'b000101_0_0_000_00_00_00_01_0000_0000_01_00_1111_1000_0110_0011_0111_0110_0011_0011;		// Synth Bass ~~ Bow wow 	Triangular wave
        7'h43: mem_q <= 63'b010110_0_0_000_00_00_00_10_0011_0001_10_00_1111_1111_0001_0100_0011_0010_0001_0011;		// Piano ~~ Electric Guitar 	Despite of its name, same as Piano of YM2413.
        7'h44: mem_q <= 63'b001011_0_1_111_00_10_11_10_0001_0001_00_00_1111_0110_1001_0100_0111_0001_0000_0111;		// Flute ~~ Organ 	Sine wave 
        7'h45: mem_q <= 63'b011110_0_0_110_00_00_01_00_0010_0001_00_00_1111_0111_1001_0110_0000_0010_0000_1000;		// Square Wave ~~ Clarinet 	Same as ones of YM2413. 
        7'h46: mem_q <= 63'b000010_0_1_110_00_01_01_00_0000_0001_10_00_1111_0110_1001_0001_0010_0010_0000_0111;		// Space Oboe ~~ Saxophone 	Saw wave with vibrato 
        7'h47: mem_q <= 63'b011011_0_0_111_00_01_11_00_0001_0001_00_00_1000_1000_0100_1111_0001_0000_0000_0111;		// Trumpet ~~ Trumpet 	Same as ones of YM2413. 
        7'h48: mem_q <= 63'b001010_0_0_010_00_00_11_11_0111_0010_11_00_0110_0110_0110_0100_0100_0010_0111_1001;		// Wow Bell ~~ Street Organ 	Calliope 
        7'h49: mem_q <= 63'b000111_0_0_011_00_11_00_00_0001_0001_00_00_1111_0111_0101_0000_0101_1111_0001_0101;		// Electric Guitar ~~ Synth Brass 	Same as Synthesizer of YM2413. 
        7'h4A: mem_q <= 63'b011110_0_0_111_00_00_10_10_0110_0001_01_00_1111_1111_0010_0011_1111_1111_0111_0111;		// Vibes ~~ Electric Piano 	Simulate of Rhodes Piano 
        7'h4B: mem_q <= 63'b011000_0_0_110_00_00_00_00_0000_0000_00_00_1100_1111_0101_0011_0010_1111_0000_0010;		// Bass ~~ Bass 	Electric bass 
        7'h4C: mem_q <= 63'b100101_0_0_111_01_00_00_10_0111_0001_00_00_1111_1111_0111_0011_0010_1111_0001_0111;		// Vibraphone ~~ Vibraphone	Same as ones of YM2413.
        7'h4D: mem_q <= 63'b000000_0_0_000_00_01_11_10_0101_0100_00_00_1111_1111_1111_0011_0111_1111_0111_0101;		// Vibrato Bell ~~ Chime 	Bell 
        7'h4E: mem_q <= 63'b000000_0_0_111_00_00_01_11_0001_0001_00_00_1101_1111_1101_0011_1111_1111_1111_1011;		// Click Sine ~~ Tom Tom II 	Tom 
        7'h4F: mem_q <= 63'b000000_0_0_111_00_00_11_10_1010_0001_00_00_1001_1000_0101_0100_0000_1111_1111_0101;		// Noise and Tone ~~ Noise 	for S.E. 

        7'h50: mem_q <= 63'b011000_0_1_111_00_00_00_00_0001_0000_00_00_1101_0000_1111_0000_0110_0000_1010_0000;		//bass drum 0
        7'h51: mem_q <= 63'b000000_0_0_000_00_00_00_00_0001_0000_00_00_1100_0000_1000_0000_1010_0000_0111_0000;		//hi hat     
        7'h52: mem_q <= 63'b000000_0_0_000_00_00_00_00_0101_0000_00_00_1111_0000_1000_0000_0101_0000_1001_0000;		//tom tom    
        7'h53: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1111_0000_1000_0000_0110_0000_1101;		//bass drum 1
        7'h54: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1101_0000_1000_0000_0100_0000_1000;		//snare drum 
        7'h55: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1010_0000_1010_0000_0101_0000_0101;		//top cymbal 

        //VRC7 patches
        7'h60: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;
        7'h61: mem_q <= 63'b000101_0_0_110_00_00_01_00_0011_0001_00_00_1100_1000_1000_0001_0100_0010_0010_0111;		// Buzzy Bell
        7'h62: mem_q <= 63'b010100_0_1_101_00_01_00_10_0011_0001_00_00_1111_1111_1000_0111_0010_0001_0011_0010;		// Guitar
        7'h63: mem_q <= 63'b001000_0_1_000_00_00_10_11_0001_0001_00_00_1111_1100_1010_0010_0010_0010_1000_0010;		// Wurly
        7'h64: mem_q <= 63'b001100_0_0_111_00_01_11_10_0001_0001_00_00_1111_0110_1000_0100_0110_0010_0000_0111;		// Flute
        7'h65: mem_q <= 63'b011110_0_0_110_00_00_11_00_0010_0001_00_00_1111_0111_1111_0110_0000_0010_0000_1000;		// Clarinet
        7'h66: mem_q <= 63'b000101_0_0_000_00_00_00_00_0010_0001_00_00_1010_1111_1100_0010_0000_0000_0011_0010;		// Synth
        7'h67: mem_q <= 63'b011101_0_0_111_00_01_11_00_0001_0001_00_00_1000_1000_0010_1111_0001_0000_0000_0111;		// Trumpet
        7'h68: mem_q <= 63'b100010_1_0_111_00_00_11_00_0011_0001_00_00_1111_0111_1111_0011_0000_0001_0000_0111;		// Organ
        7'h69: mem_q <= 63'b100101_0_0_000_00_00_00_11_0101_0001_00_00_0100_0111_0001_0001_0000_1111_0000_0001;		// Bells
        7'h6A: mem_q <= 63'b010000_0_1_111_10_00_00_10_0101_0001_00_00_1011_1010_1000_1010_0101_0000_0000_0010;		// Vibes
        7'h6B: mem_q <= 63'b011110_0_0_111_01_01_00_10_0111_0001_01_00_1111_1111_1010_1000_0010_0001_0010_0010;		// Vibraphone
        7'h6C: mem_q <= 63'b010001_0_0_110_00_10_11_10_0001_0011_00_00_0110_0111_0101_0100_0001_0001_0000_0110;		// Tutti
        7'h6D: mem_q <= 63'b010011_0_0_101_00_00_00_00_0001_0010_11_00_1111_1001_0011_0010_1000_1111_0011_0010;		// Fretless
        7'h6E: mem_q <= 63'b001100_0_0_000_00_11_11_00_0001_0011_00_00_1010_1111_0100_1111_0011_0000_0000_0110;		// Synth Bass
        7'h6F: mem_q <= 63'b001101_0_0_000_00_01_11_00_0001_0010_00_00_1010_1111_0001_1111_0101_0000_0000_1000;		// Sweep

        7'h70: mem_q <= 63'b011000_0_1_111_00_00_00_00_0001_0000_00_00_1101_0000_1111_0000_0110_0000_1010_0000;		//bass drum 0
        7'h71: mem_q <= 63'b000000_0_0_000_00_00_00_00_0001_0000_00_00_1100_0000_1000_0000_1010_0000_0111_0000;		//hi hat     
        7'h72: mem_q <= 63'b000000_0_0_000_00_00_00_00_0101_0000_00_00_1111_0000_1000_0000_0101_0000_1001_0000;		//tom tom    
        7'h73: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1111_0000_1000_0000_0110_0000_1101;		//bass drum 1
        7'h74: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1101_0000_1000_0000_0100_0000_1000;		//snare drum 
        7'h75: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0001_00_00_0000_1010_0000_1010_0000_0101_0000_0101;		//top cymbal 

        default: mem_q <= 63'b000000_0_0_000_00_00_00_00_0000_0000_00_00_0000_0000_0000_0000_0000_0000_0000_0000;   
    endcase
end
end
endgenerate



///////////////////////////////////////////////////////////
//////  Data selector
////

reg             m_nc_sel_z;
always @(posedge i_EMUCLK) if(!i_phi1_PCEN_n) m_nc_sel_z <= i_MnC_SEL; //delay select bit to select data properly

assign  o_RR_ROM   = m_nc_sel_z ? mem_q[7:4] : mem_q[3:0];
assign  o_SL_ROM   = m_nc_sel_z ? mem_q[15:12] : mem_q[11:8];
assign  o_DR_ROM   = m_nc_sel_z ? mem_q[23:20] : mem_q[19:16];
assign  o_AR_ROM   = m_nc_sel_z ? mem_q[31:28] : mem_q[27:24];

assign  o_KSL_ROM  = m_nc_sel_z ? mem_q[35:34] : mem_q[33:32];

assign  o_MUL_ROM  = m_nc_sel_z ? mem_q[43:40] : mem_q[39:36];

assign  o_KSR_ROM  = m_nc_sel_z ? mem_q[45] : mem_q[44];
assign  o_ETYP_ROM = m_nc_sel_z ? mem_q[47] : mem_q[46];
assign  o_PM_ROM   = m_nc_sel_z ? mem_q[49] : mem_q[48];
assign  o_AM_ROM   = m_nc_sel_z ? mem_q[51] : mem_q[50];

assign  o_FB_ROM   = mem_q[54:52];

assign  o_DM_ROM   = mem_q[55];
assign  o_DC_ROM   = mem_q[56];

assign  o_TL_ROM   = mem_q[62:57];

endmodule