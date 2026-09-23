vlib work
vlog Gowin_rPLL.v
vlog Gowin_rPLL2.v
vlog Gowin_CLKDIV.v
vlog DVI_TX_Top.v
vlog +timescale+1ps/1ps ..\ws2812_led\ip_ws2812_led.v
vlog +timescale+1ps/1ps ..\debugger\ip_debugger.v
vlog +timescale+1ps/1ps ..\msx_slot\msx_slot.v
vlog +timescale+1ps/1ps ..\v9968\vdp_color_palette_ram.v
vlog +timescale+1ps/1ps ..\v9968\vdp_color_palette.v
vlog +timescale+1ps/1ps ..\v9968\vdp_command_cache.v
vlog +timescale+1ps/1ps ..\v9968\vdp_command.v
vlog +timescale+1ps/1ps ..\v9968\vdp_cpu_interface.v
vlog +timescale+1ps/1ps ..\v9968\vdp_sprite_divide_table.v
vlog +timescale+1ps/1ps ..\v9968\vdp_sprite_info_collect.v
vlog +timescale+1ps/1ps ..\v9968\vdp_sprite_makeup_pixel.v
vlog +timescale+1ps/1ps ..\v9968\vdp_sprite_select_visible_planes.v
vlog +timescale+1ps/1ps ..\v9968\vdp_timing_control_screen_mode.v
vlog +timescale+1ps/1ps ..\v9968\vdp_timing_control_sprite.v
vlog +timescale+1ps/1ps ..\v9968\vdp_timing_control_ssg.v
vlog +timescale+1ps/1ps ..\v9968\vdp_timing_control.v
vlog +timescale+1ps/1ps ..\v9968\vdp_upscan_line_buffer.v
vlog +timescale+1ps/1ps ..\v9968\vdp_upscan.v
vlog +timescale+1ps/1ps ..\v9968\vdp_video_double_buffer.v
vlog +timescale+1ps/1ps ..\v9968\vdp_video_out_bilinear.v
vlog +timescale+1ps/1ps ..\v9968\vdp_video_out.v
vlog +timescale+1ps/1ps ..\v9968\vdp_video_ram_line_buffer.v
vlog +timescale+1ps/1ps ..\v9968\vdp_vram_interface.v
vlog +timescale+1ps/1ps ..\v9968\vdp.v
vlog +timescale+1ps/1ps ..\sdram\ip_sdram_tangnano20k_c.v
vlog +timescale+1ps/1ps MT48LC2M32B2.v
vlog +timescale+1ps/1ps ..\FPGA_MSXtR_VDP_Stack.v
vlog tb.sv
vsim -c -t 1ps -do run.do tb
move transcript log.txt
pause
