

module bfly_acc_top
# (
  // AXI Spec
  parameter DATA_WIDTH_AXI = 128,
  // Engine Spec
  parameter data_width     = 16,
  parameter be_parallelism = 76,
  parameter bu_parallelism = 8,

  parameter latency_add    = 3,
  parameter latency_mul    = 3,
  parameter caddsub_delay  = 3
) (
  input wire                   sys_clk,
  input wire                   rst_n,
  
  input  wire                        is_fft,      // is fft
  input  wire                        is_sc_add,
  input  wire                        is_sc_cache,
  input  wire  [16-1:0]              num_seq,        // num_seq flag for transpose buffer
  input  wire  [16-1:0]              length,
  input  wire  [8-1:0]               sub_parallelsim,
  input  wire                        is_bypass_p2s,
  input  wire                        keep_last_num,
  // 加速器状态监测
  // output wire                                   butterfly_starts,
  // output wire                                   butterfly_finish,
  // output   reg  [16-1:0]                        model_end_counter,

  input wire                         weight_vld,
  input wire                         data_vld,
  input wire [DATA_WIDTH_AXI-1:0]    input_dat,
  output                                  up_rdy,

  output wire  [DATA_WIDTH_AXI-1 : 0]     dn_parallel_dat,
  output wire                             dn_parallel_vld,
  input                                   dn_rdy
);

// =========================================================================== //
// Instantiate Input Weight Pack
// =========================================================================== //
wire [(4*data_width)*bu_parallelism-1:0]  pad_weight_dat;
wire                                      pad_weight_vld;

  data_pack # (
    .OUT_WIDTH(4*bu_parallelism*data_width),
    .IN_WIDTH(DATA_WIDTH_AXI)
  ) u_weight_pack
  (
    //////////////////clock & control signals/////////////////
    .clk(sys_clk),
    .rst_n(rst_n), 
    //////////////////Up data and signals/////////////
    .up_dat(input_dat),
    .up_vld(weight_vld),
    .up_rdy(),
    //////////////////Up data and signals/////////////
    .dn_dat(pad_weight_dat), // assume ddr bandwidht is 256*8, input buffer bandwidth is 128*32
    .dn_vld(pad_weight_vld),
    .dn_rdy(1'b1)
  );

// =========================================================================== //
// Instantiate Input Data Pack
// =========================================================================== //

wire [(2*data_width)*be_parallelism-1:0]       pad_input_dat;  // input 32k, square later
wire                                           pad_input_vld;

  data_pack # (
    .OUT_WIDTH(2*be_parallelism*data_width),
    .IN_WIDTH(DATA_WIDTH_AXI)
  ) u_data_in_pack
  (  //////////////////clock & control signals/////////////////
    .clk(sys_clk),
    .rst_n(rst_n), 
    //////////////////Up data and signals/////////////
    .up_dat(input_dat),
    .up_vld(data_vld),
    .up_rdy(),
    //////////////////Up data and signals/////////////
    .dn_dat(pad_input_dat),
    .dn_vld(pad_input_vld),
    .dn_rdy(1'b1)
  );

// =========================================================================== //
// Instantiate Butterfly Process
// =========================================================================== //
 
wire                                                         dn_vld_A; 
wire                                                         dn_vld_B;

wire  [data_width*be_parallelism-1:0]             dn_serial_dat_A; // real
wire  [data_width*be_parallelism-1:0]             dn_serial_dat_B;

  butterfly_processor # (
    .data_width(data_width),
    .be_parallelism(be_parallelism),
    .bu_parallelism(bu_parallelism),
    .latency_add(latency_add),
    .latency_mul(latency_mul),
    .caddsub_delay(caddsub_delay)
  ) u_bp (
    .clk(sys_clk),
    .rst_n(rst_n),

    //=================control signal=====================//
    .is_fft(is_fft), 
    .is_sc_add(is_sc_add),
    .is_sc_cache(is_sc_cache),
    .num_seq(num_seq),
    .length(length),
    .sub_parallelsim(sub_parallelsim),
    .is_bypass_p2s(is_bypass_p2s),
    .keep_last_num(keep_last_num),
    .clear_counter(1'b0),
    // Accel. status return
    .butterfly_start(),
    .butterfly_finish(),
    .model_end_counter(),
    //===================================================//
    .up_weight_dat(pad_weight_dat), //Wb4, 3, 2, 1
    .up_weight_vld(pad_weight_vld),
    //=================input and output=====================//
    .up_axi_serial_vld(pad_input_vld),
    .up_axi_serial_dat(pad_input_dat),
    .up_rdy (up_rdy),

    // Port A
    // down stream data output for FFT
    .dn_serial_vld_A(dn_vld_A), 
    .dn_serial_dat_A(dn_serial_dat_A),
    .dn_serial_rdy_A(1'b1),

    .dn_parallel_vld_A(), 
    .dn_parallel_dat_A(),
    .dn_parallel_rdy_A(1'b1),

    // Port B
    // down stream data output for FFT
    .dn_serial_vld_B(dn_vld_B), 
    .dn_serial_dat_B(dn_serial_dat_B),
    .dn_serial_rdy_B(1'b1),

    .dn_parallel_vld_B(), 
    .dn_parallel_dat_B(),
    .dn_parallel_rdy_B(1'b1)
  );

// =========================================================================== //
// Instantiate Output data width converter
// because of relation between bandwidth and output behave one converter works fine.
// =========================================================================== //
//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG

axis_dwidth_converter_0  u_output_dwc (
  .aclk(sys_clk),                    // input wire aclk
  .aresetn(rst_n),              // input wire aresetn
  .s_axis_tvalid(dn_vld_A | dn_vld_B),  // input wire s_axis_tvalid
  .s_axis_tready(),  // output wire s_axis_tready
  .s_axis_tdata({dn_serial_dat_A, dn_serial_dat_B}),   // input wire [4095 : 0] s_axis_tdata
  .m_axis_tvalid(dn_parallel_vld),  // output wire m_axis_tvalid
  .m_axis_tready(dn_rdy),  // input wire m_axis_tready
  .m_axis_tdata(dn_parallel_dat)   // output wire [511 : 0] m_axis_tdata
);   

endmodule
