vlib work

rem ---- PLL replacement models (Gowin hard macro substitutes) ----
vlog gowin_rpll.v

rem ---- Z80 CPU core ----
vlog ..\cz80\cz80_alu.v
vlog ..\cz80\cz80_mcode.v
vlog ..\cz80\cz80_reg.v
vlog ..\cz80\cz80.v
vlog ..\cz80\cz80_inst.v

rem ---- R800 CPU core ----
vlog ..\cr800\cr800_alu.v
vlog ..\cr800\cr800_mcode.v
vlog ..\cr800\cr800_reg.v
vlog ..\cr800\cr800.v
vlog ..\cr800\cr800_inst.v

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

rem ---- V9958 (VDP sub-modules) ----
vlog ..\v9958\vdp_color_palette_ram.v
vlog ..\v9958\vdp_color_palette.v
vlog ..\v9958\vdp_command.v
vlog ..\v9958\vdp_cpu_interface.v
vlog ..\v9958\vdp_sprite_info_collect.v
vlog ..\v9958\vdp_sprite_makeup_pixel.v
vlog ..\v9958\vdp_sprite_select_visible_planes.v
vlog ..\v9958\vdp_timing_control_screen_mode.v
vlog ..\v9958\vdp_timing_control_sprite.v
vlog ..\v9958\vdp_timing_control_ssg.v
vlog ..\v9958\vdp_timing_control.v
vlog ..\v9958\vdp_upscan_line_buffer.v
vlog ..\v9958\vdp_upscan.v
vlog ..\v9958\vdp_video_double_buffer.v
vlog ..\v9958\vdp_video_out_bilinear.v
vlog ..\v9958\vdp_video_out.v
vlog ..\v9958\vdp_video_ram_line_buffer.v
vlog ..\v9958\vdp_vram_interface.v
vlog ..\v9958\vdp.v

rem ---- SSRAM ----
vlog ..\ssram\ssram_test_model.v
vlog ..\ssram\ssram.v

rem ---- Kanji ROM ----
vlog ..\kanji_rom\kanji_rom.v

rem ---- SDRAM ----
vlog ..\sdram\ip_sdram_tangnano20k_c.v
vlog MT48LC2M32B2.v

rem ---- System controller ----
vlog ..\s2026a\s2026a.v

rem ---- Top module and testbench ----
rem NOTE: Stubs remain in tb.sv for modules with port mismatches or no source:
rem   cz80_inst, cr800_inst  (module cz80 name collision between cz80.v and cr800.v)
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
