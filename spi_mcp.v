//
// "MiSTer Vector" DAC Board logic.
//
// ElectronAsh (2020).
// 
// 
// WIP PCB design is here...
// https://github.com/ElectronAsh/MiSTer_Vector 
//
//
// Uses three MCP4922 12-bit SPI DACs, connected to the "USER_IO" port.
//
//
// Data is now being shifted into all three DAC chips at once.
//
// Requires 16 bits per DAC channel, as there are 4 "command" bits, plus the 12 data bits.
//
// Also requires CS_N to go High between shifting the data out (which then latches the data into the DAC chip's input register).
//
// Then a final LAT_N pulse which lasts two clock cycles (at the rated maximum 20 MHz SPI freq), plus a few other clock gaps.
//
// 37 clock cycles total, to shift the data out to three DAC chips.
//
// Two DAC channels per chip, so six channels.
//
// with a 20 MHz SPI clock freq, that gives a DAC update rate of around 648 KHz.
//
module spi_mcp (
	input clock,
	input reset_n,
	
	input [11:0] dac_x,
	input [11:0] dac_y,
	input [11:0] dac_r,
	input [11:0] dac_g,
	input [11:0] dac_b,
	input [11:0] dac_i,
	
	input dac_x_latch,
	input dac_y_latch,
	input dac_r_latch,
	input dac_g_latch,
	input dac_b_latch,
	input dac_i_latch,
	
	output dac_sclk,
	output reg dac_cs_n,
	output reg dac_lat_n,
	
	output dac_sdat_xy,
	output dac_sdat_rg,
	output dac_sdat_bi
);

/*
reg [1:0] clk_div;
always @(posedge clock) clk_div <= clk_div + 1;
assign sclk = clk_div[1];
assign dac_sclk = !sclk;	// Inverted the clock for the output to the DACs!
*/

assign dac_sclk = !clock;	// Inverted the clock for the output to the DACs!


reg [11:0] input_reg_x;
reg [11:0] input_reg_y;
reg [11:0] input_reg_r;
reg [11:0] input_reg_g;
reg [11:0] input_reg_b;
reg [11:0] input_reg_i;


reg [15:0] shift_reg_xy;
reg [15:0] shift_reg_rg;
reg [15:0] shift_reg_bi;

reg [5:0] bit_cnt;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	bit_cnt <= 6'd0;
	dac_cs_n <= 1'b1;
	dac_lat_n <= 1'b1;
end
else begin
	bit_cnt <= bit_cnt + 1;

	if (dac_x_latch) input_reg_x <= dac_x;
	if (dac_y_latch) input_reg_y <= dac_y;
	if (dac_r_latch) input_reg_r <= dac_r;
	if (dac_g_latch) input_reg_g <= dac_g;
	if (dac_b_latch) input_reg_b <= dac_b;
	if (dac_i_latch) input_reg_i <= dac_i;

	if (bit_cnt==0) begin
		shift_reg_xy <= {4'b0111, input_reg_x};	// [15]=DAC_A. [14]=BUF. [13]=GAIN. [12]=SHDNB. [11:0]=Data. Note: DACA and DACB are swapped for X and Y on the schematic!
		shift_reg_rg <= {4'b1111, input_reg_r};	// [15]=DAC_B. [14]=BUF. [13]=GAIN. [12]=SHDNB. [11:0]=Data.
		shift_reg_bi <= {4'b1111, input_reg_b};	// [15]=DAC_B. [14]=BUF. [13]=GAIN. [12]=SHDNB. [11:0]=Data.
	end
	
	if (bit_cnt==17) begin
		shift_reg_xy <= {4'b1111, input_reg_y};	// [15]=DAC_B. [14]=BUF. [13]=GAIN. [12]=SHDNB. [11:0]=Data. Note: DACA and DACB are swapped for X and Y on the schematic!
		shift_reg_rg <= {4'b0111, input_reg_g};	// [15]=DAC_A. [14]=BUF. [13]=GAIN. [12]=SHDNB. [11:0]=Data.
		shift_reg_bi <= {4'b0111, input_reg_i};	// [15]=DAC_A. [14]=BUF. [13]=GAIN. [12]=SHDNB. [11:0]=Data.
	end

	if ( (bit_cnt>=1 && bit_cnt<=16) || (bit_cnt>=18 && bit_cnt<=33) ) begin
		shift_reg_xy <= {shift_reg_xy[14:0],1'b0};
		shift_reg_rg <= {shift_reg_rg[14:0],1'b0};
		shift_reg_bi <= {shift_reg_bi[14:0],1'b0};
	end

	dac_cs_n <= 1'b1;	
	if ( (bit_cnt>=0 && bit_cnt<=15) || (bit_cnt>=17 && bit_cnt<=32) ) dac_cs_n <= 1'b0;

	dac_lat_n <= !(bit_cnt>=34 && bit_cnt<=35);
	
	if (bit_cnt==36) bit_cnt <= 6'd0;
end

assign dac_sdat_xy = shift_reg_xy[15];
assign dac_sdat_rg = shift_reg_rg[15];
assign dac_sdat_bi = shift_reg_bi[15];


endmodule
