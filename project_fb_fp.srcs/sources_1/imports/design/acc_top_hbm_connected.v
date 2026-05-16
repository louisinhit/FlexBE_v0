//////////////////////////////////////////////////////////////////////////////////
// Top-level integration for FlexBE butterfly_processor + VCU128 HBM shell.
//
// Purpose:
//   Resource/timing-report oriented top.  It wires the uploaded FlexBE
//   butterfly_processor to the HBM wrapper style used by the original BE VCU128
//   acc_top.  The data path is connected structurally, but no attempt is made to
//   validate algorithmic transaction scheduling.
//
// Notes:
//   - Keep DATA_WIDTH_AXI at 256 for the supplied VCU128 HBM wrapper/IP.
//   - HBM returns is_fft/length/is_bypass_p2s through hbm_control.
//   - FlexBE-only controls remain top-level inputs to avoid modifying hbm.v.
//////////////////////////////////////////////////////////////////////////////////


module bfly_acc_top_hbm
# (
  // HBM / AXI spec, matching the original VCU128 HBM shell.
  parameter AXI_CHANNELS     = 16,
  parameter ADDR_WIDTH       = 33,   // [32] selects HBM stack in original design
  parameter ID_WIDTH         = 5,
  parameter WEIGHT_AXI_CHNL  = 1,
  parameter INPUT_AXI_CHNL   = 8,
  parameter OUTPUT_AXI_CHNL  = 8,
  parameter DATA_WIDTH_AXI   = 256,

  // FlexBE butterfly processor spec.
  parameter data_width              = 16,
  parameter be_parallelism          = 76,
  parameter parallelism_per_control = 4,
  parameter bu_parallelism          = 8,
  parameter latency_add             = 3,
  parameter latency_mul             = 3,
  parameter caddsub_delay           = 3
) (
  ////////////////// clocks / reset //////////////////
  input wire                         sys_clk,
  input wire                         ddr0_clk,
  input wire                         rst_n,

  ////////////////// HBM parameter programming //////////////////
  input wire [ADDR_WIDTH-1:0]         params,

  ////////////////// control and data for input buffer //////////////////
  input wire                          start_read_input,
  input wire                          start_write_input,
  input wire [4-1:0]                  input_param_id,

  ////////////////// control and data for weight buffer //////////////////
  input wire                          start_read_weight,
  input wire                          start_write_weight,
  input wire [4-1:0]                  weight_param_id,
  input wire                          auto_write_weight,

  ////////////////// control and data for output buffer //////////////////
  input wire [3-1:0]                  output_param_id,

  ////////////////// FlexBE-only controls not present in original hbm_control //////////////////
  input wire                          is_sc_add,
  input wire                          is_sc_cache,
  input wire [16-1:0]                 num_seq,
  input wire [8-1:0]                  sub_parallelsim,
  input wire                          keep_last_num,
  input wire [3:0]                    max_pool_size,
  input wire                          clear_counter,

  ////////////////// optional status outputs //////////////////
  output wire                         up_rdy,
  output wire                         butterfly_start,
  output wire                         butterfly_finish,
  output wire [16-1:0]                model_end_counter
);

// =========================================================================== //
// Instantiate HBM wrapper
// =========================================================================== //
wire                                      weight_vld;
wire [DATA_WIDTH_AXI*WEIGHT_AXI_CHNL-1:0] weight_dat;

wire [INPUT_AXI_CHNL-1:0]                 input_vld;
wire [DATA_WIDTH_AXI*INPUT_AXI_CHNL-1:0]  input_dat;

wire                                      is_fft;
wire [32-1:0]                             hbm_length;
wire                                      is_bypass_p2s;

wire [OUTPUT_AXI_CHNL-1:0]                start_write_output;
wire [OUTPUT_AXI_CHNL*DATA_WIDTH_AXI-1:0] output_dat;

hbm # (
  .AXI_CHANNELS    (AXI_CHANNELS),
  .ADDR_WIDTH      (ADDR_WIDTH),
  .ID_WIDTH        (ID_WIDTH),
  .WEIGHT_AXI_CHNL (WEIGHT_AXI_CHNL),
  .INPUT_AXI_CHNL  (INPUT_AXI_CHNL),
  .OUTPUT_AXI_CHNL (OUTPUT_AXI_CHNL),
  .DATA_WIDTH      (DATA_WIDTH_AXI)
) u_hbm_0 (
  .sys_clk            (sys_clk),
  .ddr_clk            (ddr0_clk),
  .rst_n              (rst_n),
  .params             (params),

  // Input buffer read/write controls.
  .start_read_input   (start_read_input),
  .start_write_input  (start_write_input),
  .input_param_id     (input_param_id),
  .dn_input_vld       (input_vld),
  .dn_input_dat       (input_dat),
  .is_fft             (is_fft),
  .length             (hbm_length),
  .is_bypass_p2s      (is_bypass_p2s),

  // Weight buffer read/write controls.
  .start_read_weight  (start_read_weight),
  .start_write_weight (start_write_weight),
  .weight_param_id    (weight_param_id),
  .auto_write_weight  (auto_write_weight),
  .dn_weight_vld      (weight_vld),
  .dn_weight_dat      (weight_dat),

  // Output buffer write controls.
  .start_write_output (start_write_output),
  .output_param_id    (output_param_id),
  .up_output_dat      (output_dat)
);

// =========================================================================== //
// Pack HBM weight stream to FlexBE butterfly weight width
// =========================================================================== //
wire [(4*data_width)*bu_parallelism-1:0] pad_weight_dat;
wire                                     pad_weight_vld;

data_pack # (
  .OUT_WIDTH (4*bu_parallelism*data_width),
  .IN_WIDTH  (DATA_WIDTH_AXI*WEIGHT_AXI_CHNL)
) u_weight_pack (
  .clk     (sys_clk),
  .rst_n   (rst_n),
  .up_dat  (weight_dat),
  .up_vld  (weight_vld),
  .up_rdy  (),
  .dn_dat  (pad_weight_dat),
  .dn_vld  (pad_weight_vld),
  .dn_rdy  (1'b1)
);

// =========================================================================== //
// Pack HBM input channels to FlexBE serial input width
// =========================================================================== //
wire [(2*data_width)*be_parallelism-1:0] pad_input_dat;
wire                                     pad_input_vld;

data_pack # (
  .OUT_WIDTH (2*be_parallelism*data_width),
  .IN_WIDTH  (DATA_WIDTH_AXI*INPUT_AXI_CHNL)
) u_data_in_pack (
  .clk     (sys_clk),
  .rst_n   (rst_n),
  .up_dat  (input_dat),
  .up_vld  (|input_vld),
  .up_rdy  (),
  .dn_dat  (pad_input_dat),
  .dn_vld  (pad_input_vld),
  .dn_rdy  (1'b1)
);

// =========================================================================== //
// Instantiate FlexBE butterfly processor
// =========================================================================== //
wire                                      dn_vld_A;
wire                                      dn_vld_B;
wire [data_width*be_parallelism-1:0]      dn_serial_dat_A;
wire [data_width*be_parallelism-1:0]      dn_serial_dat_B;

butterfly_processor # (
  .data_width              (data_width),
  .be_parallelism          (be_parallelism),
  .parallelism_per_control (parallelism_per_control),
  .bu_parallelism          (bu_parallelism),
  .latency_add             (latency_add),
  .latency_mul             (latency_mul),
  .caddsub_delay           (caddsub_delay)
) u_bp (
  .clk                 (sys_clk),
  .rst_n               (rst_n),

  .is_fft              (is_fft),
  .is_sc_add           (is_sc_add),
  .is_sc_cache         (is_sc_cache),
  .num_seq             (num_seq),
  .length              (hbm_length[16-1:0]),
  .sub_parallelsim     (sub_parallelsim),
  .is_bypass_p2s       (is_bypass_p2s),
  .keep_last_num       (keep_last_num),
  .max_pool_size       (max_pool_size),

  .butterfly_start     (butterfly_start),
  .butterfly_finish    (butterfly_finish),
  .model_end_counter   (model_end_counter),
  .clear_counter       (clear_counter),

  .up_weight_dat       (pad_weight_dat),
  .up_weight_vld       (pad_weight_vld),

  .up_axi_serial_vld   (pad_input_vld),
  .up_axi_serial_dat   (pad_input_dat),
  .up_rdy              (up_rdy),

  .dn_serial_vld_A     (dn_vld_A),
  .dn_serial_dat_A     (dn_serial_dat_A),
  .dn_serial_rdy_A     (1'b1),
  .dn_parallel_vld_A   (),
  .dn_parallel_dat_A   (),
  .dn_parallel_rdy_A   (1'b1),

  .dn_serial_vld_B     (dn_vld_B),
  .dn_serial_dat_B     (dn_serial_dat_B),
  .dn_serial_rdy_B     (1'b1),
  .dn_parallel_vld_B   (),
  .dn_parallel_dat_B   (),
  .dn_parallel_rdy_B   (1'b1)
);

// =========================================================================== //
// Connect FlexBE output stream to HBM output write channels
// =========================================================================== //
localparam BP_SERIAL_WIDTH  = 2*data_width*be_parallelism;
localparam HBM_OUTPUT_WIDTH = OUTPUT_AXI_CHNL*DATA_WIDTH_AXI;

wire [BP_SERIAL_WIDTH-1:0] bp_serial_dat;
wire                       bp_serial_vld;

assign bp_serial_dat = {dn_serial_dat_A, dn_serial_dat_B};
assign bp_serial_vld = dn_vld_A | dn_vld_B;
assign start_write_output = {OUTPUT_AXI_CHNL{bp_serial_vld}};

generate
  if (BP_SERIAL_WIDTH >= HBM_OUTPUT_WIDTH) begin : GEN_TRUNCATE_BP_TO_HBM
    assign output_dat = bp_serial_dat[HBM_OUTPUT_WIDTH-1:0];
  end else begin : GEN_PAD_BP_TO_HBM
    assign output_dat = {{(HBM_OUTPUT_WIDTH-BP_SERIAL_WIDTH){1'b0}}, bp_serial_dat};
  end
endgenerate

endmodule
