
module butterfly_processor
# (
  // The data width of input data
  parameter data_width              = 16,
  parameter be_parallelism          = 40,
  parameter parallelism_per_control = 4,
  parameter bu_parallelism          = 4,
  parameter latency_add             = 1,
  parameter latency_mul             = 1,
  parameter caddsub_delay           = 1,
  parameter addr_len                = 16
)
(
  input  wire                        clk,
  input  wire                        rst_n,
  //=================control signal=====================//
  input  wire                        is_fft,      // is fft
  input  wire                        is_sc_add,
  input  wire                        is_sc_cache,
  input  wire  [16-1:0]              num_seq,        // num_seq flag for transpose buffer
  input  wire  [16-1:0]              length,
  input  wire  [8-1:0]               sub_parallelsim,
  input  wire                        is_bypass_p2s,
  input  wire                        keep_last_num,
  input  wire [3:0]                  max_pool_size,

  output wire                                   butterfly_start,
  output wire                                   butterfly_finish,
  output   reg  [16-1:0]                        model_end_counter,
  input   wire                                  clear_counter,
  //===================weight data=======================//
  input wire  [(4*data_width)*bu_parallelism-1:0]  up_weight_dat,
  input wire                                       up_weight_vld,
  //=================input and output=====================//
  input wire                                                       up_axi_serial_vld,
  input wire  [2*data_width*be_parallelism-1:0]                    up_axi_serial_dat,          // real + complex
  // input wire                                                       up_parallel_vld,
  // input wire  [(2*bu_parallelism)*data_width*2*be_parallelism-1:0]   up_parallel_dat,
  output  wire                        up_rdy,

  // Port A
  // down stream data output for FFT
  output wire                                       dn_serial_vld_A, 
  output wire  [data_width*be_parallelism-1:0]      dn_serial_dat_A, // real
  input wire                                        dn_serial_rdy_A,
  
  output wire  [be_parallelism-1:0]                                  dn_parallel_vld_A, 
  output wire  [(2*bu_parallelism)*data_width*be_parallelism-1:0]    dn_parallel_dat_A, // real
  input wire                                                         dn_parallel_rdy_A,

  // Port B
  // down stream data output for FFT
  output wire                                       dn_serial_vld_B, 
  output wire  [data_width*be_parallelism-1:0]      dn_serial_dat_B, // complex
  input wire                                        dn_serial_rdy_B,
  
  output wire  [be_parallelism-1:0]                                 dn_parallel_vld_B, 
  output wire  [(2*bu_parallelism)*data_width*be_parallelism-1:0]   dn_parallel_dat_B, // complex
  input wire                                                        dn_parallel_rdy_B
);


genvar i;

wire  [be_parallelism-1:0]                          dn_serial_vlds_A; 
wire  [data_width*parallelism_per_control-1:0]      dn_serial_dats_A[be_parallelism/parallelism_per_control-1:0]; // real
wire                                                dn_serial_rdys_A[be_parallelism/parallelism_per_control-1:0];
  
wire  [be_parallelism-1:0]                                           dn_parallel_vlds_A; 
wire  [(2*bu_parallelism)*data_width*parallelism_per_control-1:0]    dn_parallel_dats_A[be_parallelism/parallelism_per_control-1:0]; // real
wire                                                                 dn_parallel_rdys_A[be_parallelism/parallelism_per_control-1:0];

wire  [be_parallelism-1:0]                         dn_serial_vlds_B; 
wire  [data_width*parallelism_per_control-1:0]     dn_serial_dats_B[be_parallelism/parallelism_per_control-1:0]; // real
wire                                               dn_serial_rdys_B[be_parallelism/parallelism_per_control-1:0];
  
wire  [be_parallelism-1:0]                                            dn_parallel_vlds_B; 
wire  [(2*bu_parallelism)*data_width*parallelism_per_control-1:0]     dn_parallel_dats_B[be_parallelism/parallelism_per_control-1:0]; // real
wire                                                                  dn_parallel_rdys_B[be_parallelism/parallelism_per_control-1:0];

// =========================================================================== //
// Generate Up Wiring
// =========================================================================== //
wire                                             butterfly_starts   [be_parallelism/parallelism_per_control-1:0];
wire                                             butterfly_finishs  [be_parallelism/parallelism_per_control-1:0];

wire      up_rdys        [be_parallelism/parallelism_per_control-1:0];


// =========================================================================== //
// Generate Up Wiring
// =========================================================================== //
wire [2*data_width*parallelism_per_control-1:0]   up_dats          [be_parallelism/parallelism_per_control-1:0];
generate
for(i=0 ; i<be_parallelism/parallelism_per_control ; i=i+1)
begin : ASSIGN_UP_DAT
    assign up_dats[i] = up_axi_serial_dat[( 2*data_width*parallelism_per_control*i + 2*data_width*parallelism_per_control-1) : (2*data_width*parallelism_per_control*i)];
end
endgenerate

// =========================================================================== //
// Generate Downstream Ready Wiring
// =========================================================================== //
generate
for(i=0 ; i<be_parallelism/parallelism_per_control ; i=i+1)
begin : ASSIGN_DN_RDY
    assign dn_serial_rdys_A[i]   = dn_serial_rdy_A;
    assign dn_serial_rdys_B[i]   = dn_serial_rdy_B;
    assign dn_parallel_rdys_A[i] = dn_parallel_rdy_A;
    assign dn_parallel_rdys_B[i] = dn_parallel_rdy_B;
end
endgenerate

assign  up_rdy = up_rdys[0];
assign  butterfly_start  = butterfly_starts[0];
assign  butterfly_finish = butterfly_finishs[0];


always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    model_end_counter <= 0;
  end else begin

    if (clear_counter) begin
      model_end_counter <= 0;
    end
    else if (butterfly_finish) begin
      model_end_counter <= model_end_counter + 1;    // 73 indicate the end.
    end else begin
      model_end_counter <= model_end_counter;
    end
  end
end

// =========================================================================== //
// Generate Weight Buffer
// =========================================================================== //

wire [(4*data_width)*bu_parallelism-1:0]  dn_weight_dat;
wire                                      dn_weight_vld;

  weight_buffer # (
    .BU_PARALLELISM(bu_parallelism),
    .DATA_WIDTH_BRAM(data_width)
  ) u_weight_ram
  (
    //////////////////clock & control signals/////////////////
    .clk(clk),
    .rst_n(rst_n), 
    .length(length),
    .butterfly_start(butterfly_starts[0]),
    //////////////////Up data and signals/////////////
    .up_dat(up_weight_dat), // assume ddr bandwidht for wights is 256*1, input buffer bandwidth is 128*32
    .up_vld(up_weight_vld),
    .up_rdy(),
    //////////////////Up data and signals/////////////
    .dn_dat(dn_weight_dat), 
    .dn_vld(dn_weight_vld),
    .dn_rdy(1'b1)
  );


// =========================================================================== //
// Generate Butterfly Engine
// =========================================================================== //
// 这是为了减少路由压力
generate
  for(i=0 ; i<be_parallelism/parallelism_per_control ; i=i+1) begin : GENERATE_BP_ENGINE
      
      (* keep_hierarchy = "yes" *)
      butterfly_engine_opt_top # (
        .data_width(data_width),
        .bu_parallelism(bu_parallelism),
        .parallelism_per_control(parallelism_per_control),
        .latency_add(latency_add),
        .latency_mul(latency_mul),
        .caddsub_delay(caddsub_delay),
        .addr_len(addr_len)
      ) u_butterfly_engine_opt
      (
        .clk(clk),
        .rst_n(rst_n),
        .is_fft(is_fft), 
        .is_sc_cache(is_sc_cache),
        .is_sc_add(is_sc_add),
        .max_pool_size(max_pool_size),
        //===================================================//
        .butterfly_coef(dn_weight_dat), //Wb4, 3, 2, 1
        .butterfly_coef_vld(dn_weight_vld),
        //=================control signal=====================//
        .length(length),
        .num_seq(num_seq),
        .sub_parallelsim(sub_parallelsim),
        .is_bypass_p2s(is_bypass_p2s),
        .keep_last_num(keep_last_num),
        
        .butterfly_start(butterfly_starts[i]),
        .butterfly_finish(butterfly_finishs[i]),
        //=================input and output=====================//
        .up_serial_vld(up_axi_serial_vld),
        .up_serial_dat(up_dats[i]), // real + complex
        .up_parallel_vld(1'b0),
        .up_parallel_dat(),
        .up_rdy (up_rdys[i]),

        // Port A
        // down stream data output for FFT
        .dn_serial_vld_A(dn_serial_vlds_A[(i*parallelism_per_control) + parallelism_per_control - 1 : i*parallelism_per_control]), 
        .dn_serial_dat_A(dn_serial_dats_A[i]),
        .dn_serial_rdy_A(dn_serial_rdys_A[i]),

        .dn_parallel_vld_A(dn_parallel_vlds_A[(i*parallelism_per_control) + parallelism_per_control - 1 : i*parallelism_per_control]), 
        .dn_parallel_dat_A(dn_parallel_dats_A[i]),
        .dn_parallel_rdy_A(dn_parallel_rdys_A[i]),

        // Port B
        // down stream data output for FFT
        .dn_serial_vld_B(dn_serial_vlds_B[(i*parallelism_per_control) + parallelism_per_control - 1 : i*parallelism_per_control]), 
        .dn_serial_dat_B(dn_serial_dats_B[i]),
        .dn_serial_rdy_B(dn_serial_rdys_B[i]),

        .dn_parallel_vld_B(dn_parallel_vlds_B[(i*parallelism_per_control) + parallelism_per_control - 1 : i*parallelism_per_control]), 
        .dn_parallel_dat_B(dn_parallel_dats_B[i]),
        .dn_parallel_rdy_B(dn_parallel_rdys_B[i])
      );

  end
endgenerate


// =========================================================================== //
// Generate Dn Wiring
// =========================================================================== //

generate
for(i=0 ; i<be_parallelism/parallelism_per_control ; i=i+1)
begin : ASSIGN_DN_DAT
    assign dn_serial_dat_A[(data_width*parallelism_per_control*i + data_width*parallelism_per_control-1) : (data_width*parallelism_per_control*i)] = dn_serial_dats_A[i];
    assign dn_serial_dat_B[(data_width*parallelism_per_control*i + data_width*parallelism_per_control-1) : (data_width*parallelism_per_control*i)] = dn_serial_dats_B[i];
    assign dn_parallel_dat_A[((2*bu_parallelism)*data_width*parallelism_per_control*i + (2*bu_parallelism)*data_width*parallelism_per_control-1) : ((2*bu_parallelism)*data_width*parallelism_per_control*i)] = dn_parallel_dats_A[i];
    assign dn_parallel_dat_B[((2*bu_parallelism)*data_width*parallelism_per_control*i + (2*bu_parallelism)*data_width*parallelism_per_control-1) : ((2*bu_parallelism)*data_width*parallelism_per_control*i)] = dn_parallel_dats_B[i];
end
endgenerate


assign dn_serial_vld_A = dn_serial_vlds_A;
assign dn_serial_vld_B = dn_serial_vlds_B;
assign dn_parallel_vld_A = dn_parallel_vlds_A;
assign dn_parallel_vld_B = dn_parallel_vlds_B;


endmodule
