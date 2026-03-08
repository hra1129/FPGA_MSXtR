vlib work

rem ---- PLL replacement models (Gowin hard macro substitutes) ----
vlog gowin_rpll.v

rem ---- Peripherals (bus interface modules) ----
vlog ..\ppi\ppi.v
vlog ..\rtc\rtc.v
vlog ..\secondary_slot\secondary_slot_inst.v
vlog ..\ssg\ssg.v
vlog ..\megarom\megarom_wo_scc.v

rem ---- OPLL (IKAOPLL sub-modules first, then top) ----
vlog ..\opll\ikaopll\IKAOPLL_modules\IKAOPLL_primitives.v
vlog ..\opll\ikaopll\IKAOPLL_modules\IKAOPLL_dac.v
vlog ..\opll\ikaopll\IKAOPLL_modules\IKAOPLL_eg.v
vlog ..\opll\ikaopll\IKAOPLL_modules\IKAOPLL_lfo.v
vlog ..\opll\ikaopll\IKAOPLL_modules\IKAOPLL_op.v
vlog ..\opll\ikaopll\IKAOPLL_modules\IKAOPLL_pg.v
vlog ..\opll\ikaopll\IKAOPLL_modules\IKAOPLL_reg.v
vlog ..\opll\ikaopll\IKAOPLL_modules\IKAOPLL_timinggen.v
vlog ..\opll\ikaopll\IKAOPLL.v
vlog ..\opll\opll.v

rem ---- Top module and testbench ----
rem NOTE: Stubs remain in tb.sv for modules with port mismatches or no source:
rem   cz80_inst, cr800_inst  (module cz80 name collision between cz80.v and cr800.v)
rem   s2026a                 (port mismatch: body uses .clk_n, real module has clk85m)
rem   kanji_rom              (port mismatch: body uses old I/F, real module has new bus I/F)
rem   memory_mapper_inst     (port mismatch: body uses .address/.wdata, real has .bus_address/.bus_wdata)
rem   ip_sdram               (port mismatch: body uses old I/F, real module has new bus I/F)
rem   i2s_audio, vdp_inst, video_out, ip_ram  (source file not available)
rem   hdmi_tx                (VHDL with Gowin OSER10 primitive)
vlog ..\FPGA_MSXtR_body.v
vlog tb.sv

vsim -c -t 1ps -do run.do tb
move transcript log.txt
pause
