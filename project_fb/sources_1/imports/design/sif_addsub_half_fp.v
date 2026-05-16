`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Design Name: 
// Module Name: sif_add_half_fp
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module sif_addsub_half(
  input                       clk,
  input                       rst_n,
  input                       is_sub,
  input                       A_vld,
  input   [16-1:0]            A_dat,
  output                      A_rdy,
  input                       B_vld,
  input   [16-1:0]            B_dat,
  output                      B_rdy,
  output                      S_vld,
  output      [16-1:0]        S_dat,
  input                       S_rdy
    );

    
    assign A_rdy = 1'b1;
    assign B_rdy = 1'b1;
    
    //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
    fp_half_addsub u_half_fp16_addsub (
      .aclk                    (clk),                                        // input wire aclk
      .s_axis_a_tvalid         (A_vld),                  // input wire s_axis_a_tvalid
      .s_axis_a_tdata          (A_dat),                    // input wire [15 : 0] s_axis_a_tdata
      .s_axis_b_tvalid         (B_vld),                  // input wire s_axis_b_tvalid
      .s_axis_b_tdata          (B_dat),                    // input wire [15 : 0] s_axis_b_tdata
      .s_axis_operation_tvalid (A_vld & B_vld),  // input wire s_axis_operation_tvalid
      .s_axis_operation_tdata  ( {7'd0,is_sub} ),    //  0 is ADD  1 is SUB
      .m_axis_result_tvalid    (S_vld),        // output wire m_axis_result_tvalid
      .m_axis_result_tdata     (S_dat)          // output wire [15 : 0] m_axis_result_tdata
    );
    //----------- Begin Cut here for INSTANTIATION Template ---// INS

endmodule



module sif_add_half(
  input                       clk,
  input                       rst_n,
  input                       A_vld,
  input   [16-1:0]            A_dat,
  output                      A_rdy,
  input                       B_vld,
  input   [16-1:0]            B_dat,
  output                      B_rdy,
  output                      S_vld,
  output      [16-1:0]        S_dat,
  input                       S_rdy
    );

    assign A_rdy = 1'b1;
    assign B_rdy = 1'b1;
    
    //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
    fp_half_add  u_half_fp16_add (
      .aclk                    (clk),                                        // input wire aclk
      .s_axis_a_tvalid         (A_vld),                  // input wire s_axis_a_tvalid
      .s_axis_a_tdata          (A_dat),                    // input wire [15 : 0] s_axis_a_tdata
      .s_axis_b_tvalid         (B_vld),                  // input wire s_axis_b_tvalid
      .s_axis_b_tdata          (B_dat),                    // input wire [15 : 0] s_axis_b_tdata
      .m_axis_result_tvalid    (S_vld),        // output wire m_axis_result_tvalid
      .m_axis_result_tdata     (S_dat)          // output wire [15 : 0] m_axis_result_tdata
    );
    //----------- Begin Cut here for INSTANTIATION Template ---// INS

endmodule

