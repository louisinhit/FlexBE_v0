
module addr_generator
# (
  // The data width utilized for accumulated results
  parameter bu_parallelism = 16,
  parameter addr_len = 16
)
(
  input  wire                                clk,
  input  wire                                rst_n,
  input  wire [addr_len*bu_parallelism-1:0]  butterfly_indx,
  input  wire [16-1:0]                       out_counter,
  input  wire [2-1:0]                        bfly_state,
  input  wire [8-1:0]                        permute_state,
  input  wire  [16-1:0]                      num_seq,
  input  wire  [16-1:0]                      num_seq_r,

  output wire [addr_len*bu_parallelism-1:0]   read_addrs,
  output wire  [16-1:0]                       permute_rotate,
  output wire  [16-1:0]                       recover_rotate
);

localparam num_out_bits = $clog2(bu_parallelism);
// localparam seq_out_mode = 2'b01;
// localparam butterfly_mode = 2'b11;

wire [addr_len-1:0]                    read_xaddrs_r  [bu_parallelism-1:0];
wire [num_out_bits-1:0]                read_yaddrs_r [bu_parallelism-1:0];

reg  [num_out_bits-1:0]    y_position_shift [bu_parallelism-1:0];
wire [addr_len-1:0]        butterfly_indxs_r [bu_parallelism-1:0];

reg  [8-1:0]                permute_r;
reg  [16-1:0]               num_seq_r0;
reg  [16-1:0]               num_seq_r1;
reg  [2-1:0]                bfly_state_r;

reg  [16-1:0]                      xaddr_bias;

// =================== timing ===================== //
always @(posedge clk) begin
    permute_r    <= permute_state;
    bfly_state_r <= bfly_state;
    num_seq_r0   <= num_seq_r;
    num_seq_r1   <= num_seq_r0;

    if (&bfly_state) begin
        // xaddr_bias <= (num_seq - num_seq_r0) << 1;
        xaddr_bias <= num_seq - num_seq_r0;
    end else begin
        xaddr_bias <= 0;
    end
end

// =================== roataion ===================== //
assign permute_rotate = { read_yaddrs_r[0], permute_r};
assign recover_rotate = { read_yaddrs_r[0], permute_r};

genvar i;
generate
for(i=0 ; i<bu_parallelism ; i=i+1)
begin : GENERATE_WRITE_POS_SHIFT
    assign butterfly_indxs_r[i] = butterfly_indx[( addr_len*i + addr_len-1) : (addr_len*i)];

    integer j;
    always @(*) begin
        y_position_shift[i] = butterfly_indxs_r[i][num_out_bits-1:0];
        for (j=0 ; j<(addr_len-num_out_bits) ; j=j+1) begin
            y_position_shift[i] = y_position_shift[i] + butterfly_indxs_r[i][num_out_bits+j];
        end
    end
end 
endgenerate


generate
for(i=0; i<bu_parallelism; i=i+1) begin : instance_addr
    WriteAddr # (
        .ADDR_LEN(addr_len),
        .num_out_bits(num_out_bits)
        ) addr_module (
        .clk(clk),
        .rst_n(rst_n),
        .bfly_state(bfly_state),
        .butterfly_indxs_r(butterfly_indx[(addr_len*i + addr_len-1) : (addr_len*i)]),
        .y_position_shift(y_position_shift[i]),
        .out_counter(out_counter),
        .read_xaddrs_r(read_xaddrs_r[i]),
        .read_yaddrs_r(read_yaddrs_r[i])
    );
end
endgenerate

// reg   [num_out_bits-1:0]            x_permute [1:0];
// wire  [16-1:0]                      xaddr_bias;
// assign xaddr_bias = (&bfly_state_r) ? ((num_seq - num_seq_r1) * 2) : 0;

generate
for(i=0 ; i<bu_parallelism/2 ; i=i+1)
begin : GENERATE_WRITE_WIRING
    assign read_addrs[( addr_len*2*i + addr_len*2 -1) : (addr_len*2*i)] = { read_xaddrs_r[read_yaddrs_r[1]] + xaddr_bias, read_xaddrs_r[read_yaddrs_r[0]] + xaddr_bias};
end
endgenerate

// integer k;

// always @(*) begin
//     for ( k=0 ; k<bu_parallelism ; k=k+1) begin
//         if ( read_yaddrs_r[k] == 0 ) x_permute[0] = k;
//         else if ( read_yaddrs_r[k] == 1) x_permute[1] = k;
//     end
// end

endmodule



module WriteAddr #(
    parameter ADDR_LEN = 16,
    parameter num_out_bits = 5
)(
    input wire clk,
    input wire rst_n,
    input wire [1:0] bfly_state,
    input wire [ADDR_LEN-1:0] butterfly_indxs_r,
    input wire [num_out_bits-1:0] y_position_shift,
    input wire [15:0] out_counter,

    output reg [ADDR_LEN-1:0] read_xaddrs_r,
    output reg [num_out_bits-1:0] read_yaddrs_r
);

    // localparam seq_in_mode = 2'b00;
    localparam seq_out_mode = 2'b01;
    // localparam idle = 2'b10;
    localparam butterfly_mode = 2'b11;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_xaddrs_r <= 0;
            read_yaddrs_r <= 0; 
        end else begin

            if (bfly_state == butterfly_mode) begin
                read_xaddrs_r <= (butterfly_indxs_r >> num_out_bits);
                read_yaddrs_r <= y_position_shift;
            end else if (bfly_state == seq_out_mode) begin 
                read_xaddrs_r <= (out_counter >> num_out_bits);
                // read_yaddrs_r <= 0;
                read_yaddrs_r <= y_position_shift;
            end
            else begin
                read_xaddrs_r <= 0;
                read_yaddrs_r <= 0;
            end
        end
    end
    // always @(posedge clk) begin
    //     read_xaddrs_r <= 0;
    //     read_yaddrs_r <= 0; 

    //     if (bfly_state == 2'b11) begin
    //         read_xaddrs_r <= (butterfly_indxs_r >> num_out_bits);
    //         read_yaddrs_r <= y_position_shift;
    //     end else if (bfly_state == 2'b01) begin
    //         read_xaddrs_r <= (out_counter >> num_out_bits);
    //         read_yaddrs_r <= y_position_shift;
    //     end
    // end
endmodule
