`timescale 1ns / 1ps


module crossbar_read
# (
	parameter data_width     = 2,
	parameter bu2_parallelism = 32
) (
  input                                            clk,
  input                                            rst_n,
  input  wire  [bu2_parallelism * data_width-1:0]  up_dat,
  input  wire                                      up_vld,
  input  wire  [16-1:0]                            permute_rotate,
  output wire  [bu2_parallelism * data_width-1:0]  dn_dat,
  output reg                                       dn_vld
);

wire [8-1:0]         rotate;
wire [8-1:0]         permute;
wire [bu2_parallelism-1:0]    data_block [data_width-1:0];
wire [bu2_parallelism-1:0]    data_shift [data_width-1:0];

assign rotate = permute_rotate[15:8];
assign permute = permute_rotate[7:0];

wire  [bu2_parallelism * data_width-1:0]  up_permute;

genvar i, j;
generate
	for (i = 0; i<bu2_parallelism ; i= i+1) begin
		for (j = 0; j<data_width ; j= j+1) begin
			assign data_block[j][i] = up_dat[j + data_width*i];
			assign up_permute[j + data_width*i] = data_shift[j][i];
		end
	end
endgenerate


generate
	for (i = 0; i<data_width ; i= i+1) begin
		read_rotate # (
			.data_length(bu2_parallelism)  // Parameter to set the data length
		) u_read_rotate (
			.shift(rotate), //  [($clog2(data_length) -1):0] 
			.up_data(data_block[i]),  // Input data
			.dn_data(data_shift[i])   // Output data
		);
	end
endgenerate

//////////////////////////// reg for pipeline
reg [bu2_parallelism * data_width-1:0]  up_permute_r;
reg [8-1:0]                             permute_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        up_permute_r <= 0;
        permute_r    <= 0; 
		dn_vld       <= 0;
    end else begin
		up_permute_r <= up_permute;
		permute_r    <= permute;
		dn_vld       <= up_vld;
	end
end
////////////////////////////////////////////

read_permute # (
	.ports(bu2_parallelism), //      = 32,
	.data_width(data_width)
) u_read_permute (
	.up_dat(up_permute_r),
	.sel(permute_r),
	.dn_dat(dn_dat)
);

endmodule



module crossbar_write
# (
	parameter data_width     = 2,
	parameter bu2_parallelism = 32
) (
  input                                            clk,
  input                                            rst_n,
  input  wire  [bu2_parallelism * data_width-1:0]  up_dat,
  input  wire                                      up_vld,
  input  wire  [16-1:0]                            recover_rotate,
  output wire  [bu2_parallelism * data_width-1:0]  dn_dat,
  output reg                                       dn_vld
);

wire [8-1:0]         rotate;
wire [8-1:0]         recover;
wire [bu2_parallelism-1:0]    data_block [data_width-1:0];
wire [bu2_parallelism-1:0]    data_shift [data_width-1:0];

assign rotate = recover_rotate[15:8];
assign recover = recover_rotate[7:0];

wire  [bu2_parallelism * data_width-1:0]  dn_recover;

write_permute # (
	.ports(bu2_parallelism), //      = 32,
	.data_width(data_width)
) u_write_permute (
	.up_dat(up_dat),
	.sel(recover),
	.dn_dat(dn_recover)
);

//////////////////////////// reg for pipeline
reg [bu2_parallelism * data_width-1:0]  dn_recover_r;
reg [8-1:0]                             rotate_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dn_recover_r <= 0;
        rotate_r     <= 0; 
		dn_vld       <= 0;
    end else begin
		dn_recover_r <= dn_recover;
		rotate_r     <= rotate;
		dn_vld       <= up_vld;
	end
end
////////////////////////////////////////////

genvar i, j;
generate
	for (i = 0; i<bu2_parallelism ; i= i+1) begin
		for (j = 0; j<data_width ; j= j+1) begin
			assign data_block[j][i] = dn_recover_r[j + data_width*i];
			assign dn_dat[j + data_width*i] = data_shift[j][i];
		end
	end
endgenerate


generate
	for (i = 0; i<data_width ; i= i+1) begin
		write_rotate # (
			.data_length(bu2_parallelism)  // Parameter to set the data length
		) u_write_rotate (
			.shift(rotate_r), //  [($clog2(data_length) -1):0] 
			.up_data(data_block[i]),  // Input data
			.dn_data(data_shift[i])   // Output data
		);
	end
endgenerate

endmodule
