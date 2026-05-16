`timescale 1ns / 1ps


module mux_21 (
    input wire in_0,
    input wire in_1,
    input wire s,
    output wire o_mux
);
  assign o_mux = (s==0) ? in_0 : in_1;

endmodule


// right shift
module read_rotate # (
    parameter data_length = 64  // Parameter to set the data length
) (
    input [($clog2(data_length) -1):0] shift, // Shift amount
    input [data_length - 1:0]          up_data,  // Input data
    output [data_length - 1:0]         dn_data   // Output data
);

wire  [data_length - 1:0] muxconnector [($clog2(data_length)):0];

assign muxconnector[0] = up_data; // Initialize the first stage of muxconnector

genvar i, j;
generate
    
    for (j = 0; j < $clog2(data_length); j = j + 1) begin : level
        for (i = 0; i < data_length; i = i + 1) begin : bit
            if ($signed(i + (1 << j)) < data_length) begin
                mux_21 mx_0( 
                    .in_0(muxconnector[j][i]), 
                    .in_1(muxconnector[j][i + (1 << j)]), 
                    .s(shift[j]), 
                    .o_mux(muxconnector[j + 1][i])
                );
            end else begin
                mux_21 mx_1(
                    .in_0(muxconnector[j][i]), 
                    .in_1(muxconnector[j][i + (1 << j) - data_length]), 
                    .s(shift[j]), 
                    .o_mux(muxconnector[j + 1][i])
                );
            end
        end
    end

endgenerate

assign dn_data = muxconnector[$clog2(data_length)]; // Assign the final output

endmodule


// left shift
module write_rotate # (
    parameter data_length = 64  // Parameter to set the data length
) (
    input [($clog2(data_length) -1):0] shift, // Shift amount
    input [data_length - 1:0]          up_data,  // Input data
    output [data_length - 1:0]         dn_data   // Output data
);

wire  [data_length - 1:0] muxconnector [($clog2(data_length)):0];

assign muxconnector[0] = up_data; // Initialize the first stage of muxconnector

genvar i, j;
generate
    
    for (j = 0; j < $clog2(data_length); j = j + 1) begin : level
        for (i = 0; i < data_length; i = i + 1) begin : bit
            if ($signed(i - (1 << j)) >= 0) begin
                mux_21 mx_0( 
                    .in_0(muxconnector[j][i]), 
                    .in_1(muxconnector[j][i - (1 << j)]), 
                    .s(shift[j]), 
                    .o_mux(muxconnector[j + 1][i])
                );
            end else begin
                mux_21 mx_1(
                    .in_0(muxconnector[j][i]), 
                    .in_1(muxconnector[j][i + data_length - (1 << j)]), 
                    .s(shift[j]), 
                    .o_mux(muxconnector[j + 1][i])
                );
            end
        end
    end

endgenerate

assign dn_data = muxconnector[$clog2(data_length)]; // Assign the final output

endmodule