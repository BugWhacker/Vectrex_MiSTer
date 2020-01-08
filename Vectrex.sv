//============================================================================
//  Vectrex
//
//  Port to MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output  [1:0] VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,
	
	inout   [6:0] USER_IO,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
//assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd1;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd1; 

`include "build_id.v" 
localparam CONF_STR = {
	"VECTREX;;",
	"-;",
	"F,VECBINROM;",
	"OB,Skip logo,No,Yes;",
	"-;",
	"O1,Aspect ratio,4:3,16:9;",
	"O9,Frame,No,Yes;",
	"O4,Resolution,High,Low;",
	"O23,Phosphor persistance,1,2,3,4;",
	"O56,Pseudocolor,Off,1,2,3;",
	"O8,Overburn,No,Yes;",
	"OC,Port 2,Joystick,Speech;",
	"-;",
	"OA,CPU Model,1,2;",
	"-;",
	"R7,Reset;",
	"J1,Button 1,Button 2,Button 3,Button 4;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joya_0, joya_1;
wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(0),

	.joystick_analog_0(joya_0),
	.joystick_analog_1(joya_1),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1)
);

wire [9:0] audio;
assign AUDIO_L = {audio, 6'd0};
assign AUDIO_R = {audio, 6'd0};
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

wire reset = (RESET | status[0] | status[7] | buttons[1] | ioctl_download | second_reset);

reg second_reset = 0;
always @(posedge clk_sys) begin
	integer timeout = 0;

	if(ioctl_download && status[11]) timeout <= 5000000;
	else begin
		if(!timeout) second_reset <= 0;
		else begin
			timeout <= timeout - 1;
			if(timeout < 1000) second_reset <= 1;
		end
	end
end

wire hblank, vblank;

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = 1;
assign VGA_SL = 0;
assign VGA_F1 = 0;

assign VGA_HS = hblank;
assign VGA_VS = vblank;
assign VGA_DE = ~(hblank | vblank);

reg [14:0] addr_mask;
always @(posedge clk_sys) begin
	reg old_download;
	
	old_download <= ioctl_download;
	if(~old_download & ioctl_download) addr_mask <= 0;
	if(ioctl_download && ioctl_wr && (ioctl_addr[14:0] & ~addr_mask)) addr_mask <= ((addr_mask<<1)|15'd1);
end

wire [4:0] pers[4]   = '{8,4,2,1};
wire [9:0] width[2]  = '{540, 332};
wire [9:0] height[2] = '{720, 410};

wire frame_line;
wire [7:0] r,g,b;

assign VGA_R = status[9] & frame_line ? 8'h40 : r;
assign VGA_G = status[9] & frame_line ? 8'h00 : g;
assign VGA_B = status[9] & frame_line ? 8'h00 : b;

vectrex vectrex
(
	.reset(reset),
	.clock(clk_sys),
	.cpu(status[10]),

	.cart_data(ioctl_dout),
	.cart_addr(ioctl_addr),
	.cart_mask(addr_mask),
	.cart_wr(ioctl_wr & ioctl_download),
	
	.video_r(r),
	.video_g(g),
	.video_b(b),

	.video_hblank(hblank),
	.video_vblank(vblank),

	.video_width(width[status[4]]),
	.video_height(height[status[4]]),

	.color(status[6:5]),
	.pers(pers[status[3:2]]),
	.overburn(status[8]),
	.frame_line(frame_line),

	.speech_mode(status[12]),
	.audio_out(audio),

	.up_1(joystick_0[4]),
	.dn_1(joystick_0[5]),
	.lf_1(joystick_0[6]),
	.rt_1(joystick_0[7]),
	.pot_x_1(joya_0[7:0]  ? joya_0[7:0]   : {joystick_0[1], {7{joystick_0[0]}}}),
	.pot_y_1(joya_0[15:8] ? ~joya_0[15:8] : {joystick_0[2], {7{joystick_0[3]}}}),

	.up_2(joystick_1[4]),
	.dn_2(joystick_1[5]),
	.lf_2(joystick_1[6]),
	.rt_2(joystick_1[7]),
	.pot_x_2(joya_1[7:0]  ? joya_1[7:0]   : {joystick_1[1], {7{joystick_1[0]}}}),
	.pot_y_2(joya_1[15:8] ? ~joya_1[15:8] : {joystick_1[2], {7{joystick_1[3]}}}),
	
	.beam_h_out( beam_h_out ),
	.beam_v_out( beam_v_out ),
	
	.beam_blank_n_out( beam_blank_n ),
	
	.beam_blank_n_delayed_out( beam_blank_n_delayed )
);

wire beam_blank_n;
wire beam_blank_n_delayed;

wire [9:0] beam_h_out;
wire [9:0] beam_v_out;

// Note, from rattboi...
//
// 1) convert original x to signed x (extra MSB bit needed for the sign!).
// 2) subtract out 270 to "rezero" it in signed.
// 3) scale as necessary (the value should be from -270 to +270), so maybe 4x it?
// 4) add the offset for the unsigned DAC "zero" point (2047).
// 5) convert back to unsigned for the DAC.
//
(*keep*) wire signed [10:0] beam_h_signed = beam_h_out;
(*keep*) wire signed [10:0] beam_v_signed = beam_v_out;

(*keep*) wire signed [11:0] beam_h_offset = beam_h_signed - 10'sd270;
(*keep*) wire signed [11:0] beam_v_offset = beam_v_signed - 10'sd360;

(*keep*) wire signed [11:0] beam_h_scaled = (beam_h_offset * 3'sd2);
(*keep*) wire signed [11:0] beam_v_scaled = (beam_v_offset * 3'sd2);

(*keep*) wire [11:0] beam_h_done = $unsigned(beam_h_scaled) + 12'sd2047;
(*keep*) wire [11:0] beam_v_done = $unsigned(beam_v_scaled) + 12'sd2047;

spi_mcp spi_mcp_inst
(
	.clock( clk_sys ) ,						// input  clock
	.reset_n( !reset ) ,						// input  reset_n
	
	.invert_x( 1'b1 ) ,						// input  invert_x
	.invert_y( 1'b0 ) ,						// input  invert_y
	
	.dac_x( beam_h_done ) ,					// input [11:0] dac_x. (UNSIGNED! Lowest at 0. Mid-point at 2047. Highest at 4095).
	.dac_y( beam_v_done ) ,					// input [11:0] dac_y. (UNSIGNED! Lowest at 0. Mid-point at 2047. Highest at 4095).
	
	.dac_r( {12{beam_blank_n_delayed}} ) ,	// input [11:0] dac_r
	.dac_g( {12{beam_blank_n_delayed}} ) ,	// input [11:0] dac_g
	.dac_b( {12{beam_blank_n_delayed}} ) ,	// input [11:0] dac_b

	.dac_i( {12{beam_blank_n_delayed}} ) ,	// input [11:0] dac_i
	
	.dac_x_latch( 1'b1 ),					// input  dac_x_latch
	.dac_y_latch( 1'b1 ),					// input  dac_y_latch
	.dac_r_latch( 1'b1 ),					// input  dac_r_latch
	.dac_g_latch( 1'b1 ),					// input  dac_g_latch
	.dac_b_latch( 1'b1 ),					// input  dac_b_latch
	.dac_i_latch( 1'b1 ),					// input  dac_i_latch
	
	.dac_sclk( dac_sclk ) ,					// output  dac_sclk
	.dac_cs_n( dac_cs_n ) ,					// output  dac_cs_n
	.dac_lat_n( dac_lat_n ) ,				// output  dac_lat_n
	
	.dac_sdat_xy( dac_sdat_xy ) ,			// output  dac_sdat_xy
	.dac_sdat_rg( dac_sdat_rg ) ,			// output  dac_sdat_rg
	.dac_sdat_bi( dac_sdat_bi ) ,			// output  dac_sdat_bi
	
	.blank_in( beam_blank_n_delayed ) ,
	.blank_out( blank_out_n )
);

// 0 - D+/RX
// 1 - D-/TX
// 2..5 - USR1..USR4
assign USER_IO[0] = dac_sclk;
assign USER_IO[1] = dac_sdat_xy;

assign USER_IO[2] = dac_cs_n;
//assign USER_IO[3] = dac_sdat_rg;
//assign USER_IO[4] = dac_sdat_bi;
assign USER_IO[5] = dac_lat_n;


assign USER_IO[3] = beam_blank_n_delayed;	// Use the blanking direct from the core.
//assign USER_IO[3] = blank_out_n;	// Use the blanking synchronized with dac_lat_n.

endmodule
