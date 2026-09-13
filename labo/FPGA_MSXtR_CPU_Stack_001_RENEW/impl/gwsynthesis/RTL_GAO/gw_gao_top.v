module gw_gao(
    mcu_cs_n,
    mcu_sclk,
    mcu_mosi,
    mcu_miso,
    mcu_intr,
    w_bus_ctrl_write,
    w_bus_ctrl_valid,
    w_bus_ctrl_ready,
    w_bus_ctrl_rdata_en,
    w_device_write,
    w_device_valid,
    w_device_ready,
    w_device_rdata_en,
    w_device_bootrom_cs,
    w_device_bootrom_ready,
    w_device_bootrom_rdata_en,
    w_device_ppi_cs,
    w_device_ppi_ready,
    w_device_ppi_rdata_en,
    \u_msx_slot/bus_m1 ,
    \u_msx_slot/bus_io ,
    \u_msx_slot/bus_write ,
    \u_msx_slot/bus_valid ,
    \u_msx_slot/bus_ready ,
    \u_msx_slot/bus_rdata_en ,
    clk215m,
    tms_pad_i,
    tck_pad_i,
    tdi_pad_i,
    tdo_pad_o
);

input mcu_cs_n;
input mcu_sclk;
input mcu_mosi;
input mcu_miso;
input mcu_intr;
input w_bus_ctrl_write;
input w_bus_ctrl_valid;
input w_bus_ctrl_ready;
input w_bus_ctrl_rdata_en;
input w_device_write;
input w_device_valid;
input w_device_ready;
input w_device_rdata_en;
input w_device_bootrom_cs;
input w_device_bootrom_ready;
input w_device_bootrom_rdata_en;
input w_device_ppi_cs;
input w_device_ppi_ready;
input w_device_ppi_rdata_en;
input \u_msx_slot/bus_m1 ;
input \u_msx_slot/bus_io ;
input \u_msx_slot/bus_write ;
input \u_msx_slot/bus_valid ;
input \u_msx_slot/bus_ready ;
input \u_msx_slot/bus_rdata_en ;
input clk215m;
input tms_pad_i;
input tck_pad_i;
input tdi_pad_i;
output tdo_pad_o;

wire mcu_cs_n;
wire mcu_sclk;
wire mcu_mosi;
wire mcu_miso;
wire mcu_intr;
wire w_bus_ctrl_write;
wire w_bus_ctrl_valid;
wire w_bus_ctrl_ready;
wire w_bus_ctrl_rdata_en;
wire w_device_write;
wire w_device_valid;
wire w_device_ready;
wire w_device_rdata_en;
wire w_device_bootrom_cs;
wire w_device_bootrom_ready;
wire w_device_bootrom_rdata_en;
wire w_device_ppi_cs;
wire w_device_ppi_ready;
wire w_device_ppi_rdata_en;
wire \u_msx_slot/bus_m1 ;
wire \u_msx_slot/bus_io ;
wire \u_msx_slot/bus_write ;
wire \u_msx_slot/bus_valid ;
wire \u_msx_slot/bus_ready ;
wire \u_msx_slot/bus_rdata_en ;
wire clk215m;
wire tms_pad_i;
wire tck_pad_i;
wire tdi_pad_i;
wire tdo_pad_o;
wire tms_i_c;
wire tck_i_c;
wire tdi_i_c;
wire tdo_o_c;
wire [9:0] control0;
wire gao_jtag_tck;
wire gao_jtag_reset;
wire run_test_idle_er1;
wire run_test_idle_er2;
wire shift_dr_capture_dr;
wire update_dr;
wire pause_dr;
wire enable_er1;
wire enable_er2;
wire gao_jtag_tdi;
wire tdo_er1;

IBUF tms_ibuf (
    .I(tms_pad_i),
    .O(tms_i_c)
);

IBUF tck_ibuf (
    .I(tck_pad_i),
    .O(tck_i_c)
);

IBUF tdi_ibuf (
    .I(tdi_pad_i),
    .O(tdi_i_c)
);

OBUF tdo_obuf (
    .I(tdo_o_c),
    .O(tdo_pad_o)
);

GW_JTAG  u_gw_jtag(
    .tms_pad_i(tms_i_c),
    .tck_pad_i(tck_i_c),
    .tdi_pad_i(tdi_i_c),
    .tdo_pad_o(tdo_o_c),
    .tck_o(gao_jtag_tck),
    .test_logic_reset_o(gao_jtag_reset),
    .run_test_idle_er1_o(run_test_idle_er1),
    .run_test_idle_er2_o(run_test_idle_er2),
    .shift_dr_capture_dr_o(shift_dr_capture_dr),
    .update_dr_o(update_dr),
    .pause_dr_o(pause_dr),
    .enable_er1_o(enable_er1),
    .enable_er2_o(enable_er2),
    .tdi_o(gao_jtag_tdi),
    .tdo_er1_i(tdo_er1),
    .tdo_er2_i(1'b0)
);

gw_con_top  u_icon_top(
    .tck_i(gao_jtag_tck),
    .tdi_i(gao_jtag_tdi),
    .tdo_o(tdo_er1),
    .rst_i(gao_jtag_reset),
    .control0(control0[9:0]),
    .enable_i(enable_er1),
    .shift_dr_capture_dr_i(shift_dr_capture_dr),
    .update_dr_i(update_dr)
);

ao_top_0  u_la0_top(
    .control(control0[9:0]),
    .trig0_i(mcu_intr),
    .data_i({mcu_cs_n,mcu_sclk,mcu_mosi,mcu_miso,mcu_intr,w_bus_ctrl_write,w_bus_ctrl_valid,w_bus_ctrl_ready,w_bus_ctrl_rdata_en,w_device_write,w_device_valid,w_device_ready,w_device_rdata_en,w_device_bootrom_cs,w_device_bootrom_ready,w_device_bootrom_rdata_en,w_device_ppi_cs,w_device_ppi_ready,w_device_ppi_rdata_en,\u_msx_slot/bus_m1 ,\u_msx_slot/bus_io ,\u_msx_slot/bus_write ,\u_msx_slot/bus_valid ,\u_msx_slot/bus_ready ,\u_msx_slot/bus_rdata_en }),
    .clk_i(clk215m)
);

endmodule
