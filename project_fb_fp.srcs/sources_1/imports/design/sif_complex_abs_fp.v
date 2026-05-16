`timescale 1ns / 1ps

module sif_complex_abs_fp (
  input                       clk,
  input                       rst_n,
  input                       up_i_vld,
  input   [16-1:0]            up_i,
  input                       up_q_vld,
  input   [16-1:0]            up_q,

  output                      dn_vld,
  output  [16-1:0]            dn_dat
);

    wire               ii_vld;
    wire [16-1:0]      ii_dat_out;

    //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
    fp_half_mult u_half_fp16_mult_ii (
        .aclk(clk),                                  // input wire aclk
        .s_axis_a_tvalid(up_i_vld),            // input wire s_axis_a_tvalid
        .s_axis_a_tdata(up_i),              // input wire [15 : 0] s_axis_a_tdata
        .s_axis_b_tvalid(up_i_vld),            // input wire s_axis_b_tvalid
        .s_axis_b_tdata(up_i),              // input wire [15 : 0] s_axis_b_tdata
        .m_axis_result_tvalid(ii_vld),  // output wire m_axis_result_tvalid
        .m_axis_result_tdata(ii_dat_out)    // output wire [15 : 0] m_axis_result_tdata
    );


    wire               qq_vld;
    wire [16-1:0]      qq_dat_out;

    //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
    fp_half_mult u_half_fp16_mult_qq (
        .aclk(clk),                                  // input wire aclk
        .s_axis_a_tvalid(up_q_vld),            // input wire s_axis_a_tvalid
        .s_axis_a_tdata(up_q),              // input wire [15 : 0] s_axis_a_tdata
        .s_axis_b_tvalid(up_q_vld),            // input wire s_axis_b_tvalid
        .s_axis_b_tdata(up_q),              // input wire [15 : 0] s_axis_b_tdata
        .m_axis_result_tvalid(qq_vld),  // output wire m_axis_result_tvalid
        .m_axis_result_tdata(qq_dat_out)    // output wire [15 : 0] m_axis_result_tdata
    );


    wire               iq_vld;
    wire [16-1:0]      iq_dat_out;

    //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
    fp_half_add  u_fp_abs_add (
        .aclk(clk),                                  // input wire aclk
        .s_axis_a_tvalid(ii_vld),            // input wire s_axis_a_tvalid
        .s_axis_a_tdata(ii_dat_out),              // input wire [15 : 0] s_axis_a_tdata
        .s_axis_b_tvalid(qq_vld),            // input wire s_axis_b_tvalid
        .s_axis_b_tdata(qq_dat_out),              // input wire [15 : 0] s_axis_b_tdata
        .m_axis_result_tvalid(iq_vld),  // output wire m_axis_result_tvalid
        .m_axis_result_tdata(iq_dat_out)    // output wire [15 : 0] m_axis_result_tdata
    );


    ///////////   square root ip core instantiation here
    //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
    fp_half_sqr  u_fp16_square_root (
        .aclk(clk),                                  // input wire aclk
        .s_axis_a_tvalid(iq_vld),            // input wire s_axis_a_tvalid
        .s_axis_a_tdata(iq_dat_out),              // input wire [15 : 0] s_axis_a_tdata
        .m_axis_result_tvalid(dn_vld),  // output wire m_axis_result_tvalid
        .m_axis_result_tdata(dn_dat)    // output wire [15 : 0] m_axis_result_tdata
    );

endmodule
