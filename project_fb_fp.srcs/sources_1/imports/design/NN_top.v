
///////////////////////////////////////////
//// the power 2 and 3 are moved to PS side using axi
//// 没有power运算  abs运算保持并行 4 *64
///////////////////////////////////////////

module NN_top
# (
  // The data width of input data
  parameter data_width     = 16,
  parameter be_parallelism = 4,
  parameter bu_parallelism = 16,
  parameter parallelism_per_control = 2,
  parameter latency_add    = 1,
  parameter latency_mul    = 1,
  parameter caddsub_delay  = 1,
  parameter addr_len       = 16
)
(
  input  wire                        clk,
  input  wire                        rst_n,
  //===================weight data=======================//
  input wire  [(4*data_width)*bu_parallelism-1:0]  up_weight_dat,
  input wire                                       up_weight_vld,
  //=================input and output=====================//
  input wire                                                    up_axi_serial_vld,
  input wire  [2*data_width*be_parallelism-1:0]                 up_axi_serial_dat,          // real + complex
  input wire                                                    up_axi_parallel_vld,
  input wire  [(2*bu_parallelism)*data_width*2-1:0]             up_axi_parallel_dat,
  output  wire                        up_rdy,

  // Port A
  // down stream data output for FFT
  // output wire                                       dn_serial_vld_A, 
  // output wire  [data_width*be_parallelism-1:0]      dn_serial_dat_A, // real
  // input wire                                        dn_serial_rdy_A,
  output wire                                                        dn_parallel_vld_A, 
  output wire  [(2*bu_parallelism)*data_width*be_parallelism-1:0]    dn_parallel_dat_A, // real
  input wire                                                         dn_parallel_rdy_A,
  // Port B
  // down stream data output for FFT
  // output wire                                       dn_serial_vld_B, 
  // output wire  [data_width*be_parallelism-1:0]      dn_serial_dat_B, // complex
  // input wire                                        dn_serial_rdy_B,
  output wire                                                       dn_parallel_vld_B, 
  output wire  [(2*bu_parallelism)*data_width*be_parallelism-1:0]   dn_parallel_dat_B, // complex
  input  wire                                                       dn_parallel_rdy_B,
  // for AXI stream control
  output wire                                                        last_branch
);

genvar i, j;

reg  [16-1:0]                length;
reg                          is_bypass_p2s;
reg                          is_fft; 
reg                          is_sc_cache; 
reg                          is_sc_add; 
reg  [16-1:0]                num_seq;
reg  [8-1:0]                 sub_parallelsim;
reg                          keep_last_num;
reg  [3:0]                   max_pool_size;

reg [16-1:0]                fft_ctrl_counter;

wire                                   butterfly_start;
wire                                   butterfly_finish;
wire  [16-1:0]                         model_end_counter;

wire                                                        up_parallel_vld;
wire [(2*bu_parallelism)*2*data_width*be_parallelism-1:0]   up_parallel_dat;

wire  [be_parallelism-1:0]                                 dn_parallel_vlds_A; 
wire  [(2*bu_parallelism)*data_width*be_parallelism-1:0]   dn_parallel_dats_A; // real
wire                                                       dn_parallel_rdys_A;

wire  [be_parallelism-1:0]                                   dn_parallel_vlds_B; 
wire  [(2*bu_parallelism)*data_width*be_parallelism-1:0]     dn_parallel_dats_B; // real
wire                                                         dn_parallel_rdys_B;

assign last_branch = (model_end_counter == 57) ? 1'b1 : 0;


// 全局reset等待下一次 axi stream valid
reg              reset_all;

  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        reset_all <= 0;
      end else begin
        reset_all <= last_branch & dn_parallel_vld_A ;  // For timing
      end
  end


// =========================================================================== //
// Generate Butterfly Engine
// =========================================================================== //

  // (* RLOC = "X3Y1", HU_SET = "top" *)
  butterfly_processor # (
    .data_width(data_width),
    .bu_parallelism(bu_parallelism),
    .be_parallelism(be_parallelism),
    .parallelism_per_control(parallelism_per_control),
    .latency_add(latency_add),
    .latency_mul(latency_mul),
    .caddsub_delay(caddsub_delay),
    .addr_len(addr_len)
  ) u_butterfly_processor
  (
    .clk(clk),
    .rst_n(rst_n),
    //=================control signal=====================//
    .is_fft(is_fft), 
    .is_sc_add(is_sc_add),
    .is_sc_cache(is_sc_cache),
    .max_pool_size(max_pool_size),
    .num_seq(num_seq),
    .length(length),
    .sub_parallelsim(sub_parallelsim),
    .is_bypass_p2s(is_bypass_p2s),
    .keep_last_num(keep_last_num),
    // Accel. status return
    .butterfly_start(butterfly_start),
    .butterfly_finish(butterfly_finish),
    .model_end_counter(model_end_counter),
    .clear_counter(reset_all),
    //===================================================//
    .up_weight_dat(up_weight_dat), //Wb4, 3, 2, 1
    .up_weight_vld(up_weight_vld),
    //=================input and output=====================//
    .up_parallel_vld(up_parallel_vld),
    .up_parallel_dat(up_parallel_dat),
    .up_rdy (up_rdy),

    // Port A
    // down stream data output for FFT
    .dn_serial_vld_A(), 
    .dn_serial_dat_A(),
    .dn_serial_rdy_A(),

    .dn_parallel_vld_A(dn_parallel_vlds_A), 
    .dn_parallel_dat_A(dn_parallel_dats_A),
    .dn_parallel_rdy_A(dn_parallel_rdys_A),

    // Port B
    // down stream data output for FFT
    .dn_serial_vld_B(), 
    .dn_serial_dat_B(),
    .dn_serial_rdy_B(),

    .dn_parallel_vld_B(dn_parallel_vlds_B), 
    .dn_parallel_dat_B(dn_parallel_dats_B),
    .dn_parallel_rdy_B(dn_parallel_rdys_B)
  );

// =========================================================================== //
// Data transfer - Configuration Reg
// =========================================================================== //
reg  [3:0]            up_parallel_sel;
reg  [3:0]            up_buffer_sel;
reg                   output_enable;

localparam IDLE       = 4'b0000;
localparam FROM_AXI   = 4'b0001;
localparam FROM_BU    = 4'b0010;
localparam FROM_BUFF  = 4'b0100;
localparam FROM_PKG   = 4'b1000;


//======================================================
//  Example: Convert from combinational to sequential
//======================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        //------------------------------------------------
        // 复位时，对所有寄存器赋默认值
        //------------------------------------------------
        length          <= 32'd0;
        up_parallel_sel <= 0;
        up_buffer_sel   <= 0;
        is_fft          <= 1'b0;
        is_sc_add       <= 1'b0;
        is_sc_cache     <= 1'b0;
        max_pool_size   <= 4'd8;
        num_seq         <= 16'd0;
        sub_parallelsim <= 1'b0;
        is_bypass_p2s   <= 1'b0;
        keep_last_num   <= 1'b0;
        output_enable   <= 1'b0;

        fft_ctrl_counter <= 0;
    end else begin
        //=========== branch 1 start ===========//
        if (model_end_counter == 0) begin
            length          <= 32;
            up_parallel_sel <= FROM_PKG;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 0;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd8;
            num_seq         <= 256; // 1024/4
            sub_parallelsim <= 8;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
        end 

        if (model_end_counter == 1) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 0;
            is_sc_cache     <= 1;
            max_pool_size   <= 4'd8;
            num_seq         <= 256;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
        end

        if (model_end_counter == 2) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 0;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd8;
            num_seq         <= 256;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
        end

        if (model_end_counter == 3) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 1;
            is_sc_cache     <= 1;
            max_pool_size   <= 4'd8;
            num_seq         <= 32;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 1;
            output_enable   <= 0;
        end

        if (model_end_counter == 4) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 0;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd8;
            num_seq         <= 32;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
        end

        if (model_end_counter == 5) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 1;
            is_sc_cache     <= 1;
            max_pool_size   <= 4'd8;
            num_seq         <= 16;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 1;
            output_enable   <= 0;
        end

        if (model_end_counter == 6) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 0;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd8;
            num_seq         <= 16;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
        end

        //=================== branch one done =======================//
        if (model_end_counter == 7  || model_end_counter == 14 || model_end_counter == 21 ) begin
            length          <= 32;
            up_parallel_sel <= FROM_PKG;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 1;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd4;
            num_seq         <= 256;
            sub_parallelsim <= 8;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 1;
        end

        if (model_end_counter == 8  || model_end_counter == 15 || model_end_counter == 22 ||
            model_end_counter == 30 || model_end_counter == 37 || model_end_counter == 44 || 
            model_end_counter == 51 ) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 0;
            is_sc_cache     <= 1;
            max_pool_size   <= 4'd8;
            num_seq         <= 256;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
        end

        if (model_end_counter == 9  || model_end_counter == 16 || model_end_counter == 23 ||
            model_end_counter == 31 || model_end_counter == 38 || model_end_counter == 45 || 
            model_end_counter == 52 ) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 0;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd8;
            num_seq         <= 256;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
        end

        if (model_end_counter == 10 || model_end_counter == 17 || model_end_counter == 24 ||
            model_end_counter == 32 || model_end_counter == 39 || model_end_counter == 46 || 
            model_end_counter == 53 ) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 1;
            is_sc_cache     <= 1;
            max_pool_size   <= 4'd8;
            num_seq         <= 32;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 1;
            output_enable   <= 0;
        end

        if (model_end_counter == 11 || model_end_counter == 18 || model_end_counter == 25 ||
            model_end_counter == 33 || model_end_counter == 40 || model_end_counter == 47 || 
            model_end_counter == 54 ) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 0;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd8;
            num_seq         <= 32;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
        end

        if (model_end_counter == 12 || model_end_counter == 19 || model_end_counter == 26 ||
            model_end_counter == 34 || model_end_counter == 41 || model_end_counter == 48 || 
            model_end_counter == 55 ) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 1;
            is_sc_cache     <= 1;
            max_pool_size   <= 4'd8;
            num_seq         <= 16;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 1;
            output_enable   <= 0;
        end

        if (model_end_counter == 13 || model_end_counter == 20 || model_end_counter == 27 ||
            model_end_counter == 35 || model_end_counter == 42 || model_end_counter == 49 || 
            model_end_counter == 56 ) begin
            length          <= 32;
            up_parallel_sel <= FROM_BU;
            up_buffer_sel   <= FROM_AXI;
            is_fft          <= 0;
            is_sc_add       <= 0;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd8;
            num_seq         <= 16;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
        end

        //================ 4 branched done, wait for 32k fft ================//
        if (model_end_counter == 28) begin 

          if (fft_ctrl_counter < 15) begin
            length          <= 32;
            up_parallel_sel <= IDLE;
            up_buffer_sel   <= IDLE;
            is_fft          <= 0;
            is_sc_add       <= 1;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd4;
            num_seq         <= 4;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 1;

            fft_ctrl_counter <= fft_ctrl_counter + 1;

          end else begin
            length          <= 32768;                                               //// for debug
            up_parallel_sel <= FROM_BUFF;
            up_buffer_sel   <= IDLE;
            is_fft          <= 1;
            is_sc_add       <= 0;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd8;
            num_seq         <= 1;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
          end
        end

        //================ collect 32fft result and start branch 5 ================//
        if (model_end_counter == 29) begin

          if (fft_ctrl_counter < 1050) begin
            length          <= 32768;                                               //// for debug
            up_parallel_sel <= IDLE;
            up_buffer_sel   <= FROM_BU;
            is_fft          <= 1;
            is_sc_add       <= 0;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd8;
            num_seq         <= 1;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;

            fft_ctrl_counter <= fft_ctrl_counter + 1;
          end
          else begin
            length          <= 32;
            up_parallel_sel <= FROM_PKG;
            up_buffer_sel   <= IDLE;
            is_fft          <= 0;
            is_sc_add       <= 0;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd8;
            num_seq         <= 256;
            sub_parallelsim <= 8;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 0;
          end
        end

        //================ branches start 6 7 8 =================//
        if (model_end_counter == 36 || model_end_counter == 43 || model_end_counter == 50 ) begin
            length          <= 32;
            up_parallel_sel <= FROM_PKG;
            up_buffer_sel   <= IDLE;
            is_fft          <= 0;
            is_sc_add       <= 1;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd4;
            num_seq         <= 256;
            sub_parallelsim <= 8;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 1;
        end

        //================ final output =================//
        if (reset_all) begin 
          length          <= 32'd0;
          up_parallel_sel <= 0;
          up_buffer_sel   <= 0;
          is_fft          <= 1'b0;
          is_sc_add       <= 1'b0;
          is_sc_cache     <= 1'b0;
          max_pool_size   <= 4'd8;
          num_seq         <= 16'd0;
          sub_parallelsim <= 1'b0;
          is_bypass_p2s   <= 1'b0;
          keep_last_num   <= 1'b0;
          output_enable   <= 1'b0;

          fft_ctrl_counter <= 0;
        end
        else if (model_end_counter == 57) begin 
            length          <= 32;
            up_parallel_sel <= IDLE;
            up_buffer_sel   <= IDLE;
            is_fft          <= 0;
            is_sc_add       <= 1;
            is_sc_cache     <= 0;
            max_pool_size   <= 4'd4;
            num_seq         <= 4;
            sub_parallelsim <= 1;
            is_bypass_p2s   <= 1;
            keep_last_num   <= 0;
            output_enable   <= 1;
        end
    end
end



wire [2*bu_parallelism*2*data_width-1 : 0]    dn_parallel_dats    [be_parallelism-1:0];

reg                                          up_buffer_vld    [be_parallelism-1:0];
reg [2*bu_parallelism*2*data_width-1 : 0]    up_buffer_dat    [be_parallelism-1:0];

wire  [be_parallelism-1:0]                    dn_buffer_vld ;
wire [2*bu_parallelism*2*data_width-1 : 0]    dn_buffer_dat    [be_parallelism-1:0];

wire                                                      dn_pkg_vld;
wire [2*data_width*2*bu_parallelism-1:0]                  dn_pkg_dat [be_parallelism-1:0];
wire [2*data_width*2*bu_parallelism*be_parallelism-1:0]   dn_pkg_dat_r;

// Data selector for FlexBE
// assign up_parallel_vld = up_parallel_sel == FROM_PKG ? dn_abs_exp_vld[0] :      // for first layer in NN
//                          up_parallel_sel == FROM_BU ? dn_parallel_vlds_A[0] :   // for other layer in NN
//                          up_parallel_sel == FROM_BUFF ? dn_buffer_vld[0] : 0;    // for 4 32k-fft

// generate
//   for(i=0 ; i< be_parallelism ; i=i+1) begin
//     assign up_parallel_dat[ 2*bu_parallelism*2*data_width*i + 2*bu_parallelism*2*data_width - 1 : 2*bu_parallelism*2*data_width*i ] = 
//                           up_parallel_sel == FROM_PKG ? dn_abs_exp_dat[i] :
//                           up_parallel_sel == FROM_BU ? dn_parallel_dats[i] :  dn_buffer_dat[i] ;
//   end
// endgenerate

reg                                                        up_parallel_vld_reg;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    // 复位时所有有效标志置0
    up_parallel_vld_reg <= 1'b0;
  end else begin
    // 这里仅示例第 0 路，如需对每个通道复制类似逻辑，可用 for 循环
    if (up_parallel_sel == FROM_PKG)
      up_parallel_vld_reg <= dn_pkg_vld;
    else if (up_parallel_sel == FROM_BU)
      up_parallel_vld_reg <= dn_parallel_vlds_A[0];
    else if (up_parallel_sel == FROM_BUFF)
      up_parallel_vld_reg <= dn_buffer_vld[0];
    else
      up_parallel_vld_reg <= 1'b0;
  end
end

assign up_parallel_vld = up_parallel_vld_reg;

localparam WIDTH = 2 * bu_parallelism * 2 * data_width; // 实际上 = 4 * bu_parallelism * data_width

reg [WIDTH-1:0] up_parallel_dat_reg [0:be_parallelism-1];

generate
  for(i = 0; i < be_parallelism; i = i + 1) begin : gen_up_parallel_dat
    always @(posedge clk or negedge rst_n) begin
      if (!rst_n)
        up_parallel_dat_reg[i] <= {WIDTH{1'b0}};
      else begin
        if (up_parallel_sel == FROM_PKG)
          up_parallel_dat_reg[i] <= dn_pkg_dat[i];
        else if (up_parallel_sel == FROM_BU)
          up_parallel_dat_reg[i] <= dn_parallel_dats[i];
        else if (up_parallel_sel == FROM_BUFF)
          up_parallel_dat_reg[i] <= dn_buffer_dat[i];
        else
          up_parallel_dat_reg[i] <= {WIDTH{1'b0}};
      end
    end
    // 将每一路的寄存器输出拼接到一起或作为单独信号输出
    // 如果 up_parallel_dat 需要作为数组输出，则直接赋值：
    assign up_parallel_dat[ WIDTH*i +: WIDTH ] = up_parallel_dat_reg[i];
  end
endgenerate


generate
  for(i=0 ; i< be_parallelism ; i=i+1) begin : GENERATE_combine_parallel_AB
    for(j=0 ; j<2*bu_parallelism ; j=j+1) begin
      assign dn_parallel_dats[i][(2*data_width*j + 2*data_width-1) : (2*data_width*j)] =
                                  {dn_parallel_dats_B[ 2*bu_parallelism*data_width*i + data_width*j + data_width - 1 : 2*bu_parallelism*data_width*i + data_width*j ],
                                  dn_parallel_dats_A[ 2*bu_parallelism*data_width*i + data_width*j + data_width - 1 : 2*bu_parallelism*data_width*i + data_width*j ]};
    end
  end
endgenerate

// =========================================================================== //
// Branch Data Buffer 
// =========================================================================== //

localparam buffer_depth = 1024;    // 32768/2/16
localparam w            = $clog2(buffer_depth);
localparam s            = $clog2(buffer_depth/be_parallelism);

wire                            write_done [be_parallelism-1:0];
reg  [w:0]                      write_data_depth;     // buffer depth
reg  [w:0]                      read_data_depth;      // buffer depth
reg  [w-1:0]                    read_counter_branch;  // buffer depth - 1

reg                                            branch_buffer_load [be_parallelism-1:0];
reg  [w:0]                  write_addr_bias [be_parallelism-1:0];
reg  [w:0]                  read_addr_bias  [be_parallelism-1:0];
reg  [2:0]                              branch_counter;  // this controls the buffer number to read for 4 32k-fft

reg                                   read_counter_clear;
reg                                   be_done_flag;


always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    read_data_depth     <= buffer_depth;
    read_counter_branch <= 0;
    branch_counter      <= 0;
    read_counter_clear  <= 1'b1;
    be_done_flag        <= 1'b1;
    branch_buffer_load[0] <= 0;
    branch_buffer_load[1] <= 0;
    branch_buffer_load[2] <= 0;
    branch_buffer_load[3] <= 0;
  end else begin

     if (write_done[1] && (model_end_counter == 0)) begin
      be_done_flag <= 0;
     end  
    // branch 1
    else if ((be_done_flag == 0) && (model_end_counter == 0)) begin
      branch_counter <= 0;

      if (!be_done_flag) begin
        read_addr_bias[0] <= read_counter_branch[(w-1):2] + (read_counter_branch[1:0] << s); // 相当于 (cnt[1:0] << 7)
        branch_buffer_load[0] <= 1'b1;// turn on this read enable

        // 计数器自增，超过 511 则回0
        if (read_counter_branch == (buffer_depth - 1)) begin
          read_counter_branch <= 0;
          be_done_flag <= 1'b1;
        end else begin
          read_counter_branch <= read_counter_branch + 1'b1;
        end
      end
    end
    else if (model_end_counter == 0) begin
        branch_buffer_load[0] <= 1'b0;
        read_counter_branch <= 0;
    end
    
    // branch 2
    if (model_end_counter == 7) begin
      branch_counter <= 1;

      if (be_done_flag) begin
        read_addr_bias[1] <= read_counter_branch[(w-1):2] + (read_counter_branch[1:0] << s); // 相当于 (cnt[1:0] << 7)
        branch_buffer_load[1] <= 1'b1;// turn on this read enable

        // 计数器自增，超过 511 则回0
        if (read_counter_branch == (buffer_depth - 1)) begin
          read_counter_branch <= 0;
          be_done_flag <= 1'b0;
        end else begin
          read_counter_branch <= read_counter_branch + 1'b1;
        end

      end else begin
        branch_buffer_load[1] <= 1'b0;
        read_counter_branch <= 0;
      end
      
    end

    // branch 3
    if (model_end_counter == 14) begin
      branch_counter <= 2;

      if (!be_done_flag) begin
        read_addr_bias[2] <= read_counter_branch[(w-1):2] + (read_counter_branch[1:0] << s); // 相当于 (cnt[1:0] << 7)
        branch_buffer_load[2] <= 1'b1;// turn on this read enable

        // 计数器自增，超过 511 则回0
        if (read_counter_branch == (buffer_depth - 1)) begin
          read_counter_branch <= 0;
          be_done_flag <= 1'b1;
        end else begin
          read_counter_branch <= read_counter_branch + 1'b1;
        end

      end else begin
        branch_buffer_load[2] <= 1'b0;
        read_counter_branch <= 0;
      end
    end

    // branch 4
    if (model_end_counter == 21) begin
      branch_counter <= 3;

      if (be_done_flag) begin
        read_addr_bias[3] <= read_counter_branch[(w-1):2] + (read_counter_branch[1:0] << s); // 相当于 (cnt[1:0] << 7)
        branch_buffer_load[3] <= 1'b1;// turn on this read enable

        // 计数器自增，超过 511 则回0
        if (read_counter_branch == (buffer_depth - 1)) begin
          read_counter_branch <= 0;
          be_done_flag <= 1'b0;
        end else begin
          read_counter_branch <= read_counter_branch + 1'b1;
        end

      end else begin
        branch_buffer_load[3] <= 1'b0;
        read_counter_branch <= 0;
      end
    end

    if ((model_end_counter == 28) && (fft_ctrl_counter >= 15)) begin    /// 开始传送 4 32k fft数据
      read_data_depth <= buffer_depth;
      read_counter_clear <= 0;
      branch_buffer_load[0] <= 1'b1;
      branch_buffer_load[1] <= 1'b1;
      branch_buffer_load[2] <= 1'b1;
      branch_buffer_load[3] <= 1'b1;
    end

    // 32k-fft complete
    if (model_end_counter == 29) begin
      // start writing back to buffer
      if (write_done[0]) begin
        // collect all the data from 32k-fft
        read_counter_clear <= 1'b1;
        be_done_flag <= 1'b1;
        branch_counter <= 0;
      end else if (!be_done_flag) begin
        branch_buffer_load[0] <= 0;
        branch_buffer_load[1] <= 0;
        branch_buffer_load[2] <= 0;
        branch_buffer_load[3] <= 0;
        read_counter_branch   <= 0;
      end
    
      if (be_done_flag && (fft_ctrl_counter >= 1050) ) begin
        // start load branch 5
        read_addr_bias[0] <= read_counter_branch[(w-1):2] + (read_counter_branch[1:0] << s); // 相当于 (cnt[1:0] << 7)
        branch_buffer_load[0] <= 1'b1;// turn on this read enable

        // 计数器自增，超过 511 则回0
        if (read_counter_branch == (buffer_depth - 1)) begin
          read_counter_branch <= 0;
          be_done_flag <= 0;
        end else begin
          read_counter_branch <= read_counter_branch + 1'b1;
        end
      end 
    end
    
    // branch 6
    if (model_end_counter == 36) begin
      branch_counter <= 1;

      if (!be_done_flag) begin
        read_addr_bias[1] <= read_counter_branch[(w-1):2] + (read_counter_branch[1:0] << s); // 相当于 (cnt[1:0] << 7)
        branch_buffer_load[1] <= 1'b1;// turn on this read enable

        // 计数器自增，超过 511 则回0
        if (read_counter_branch == (buffer_depth - 1)) begin
          read_counter_branch <= 0;
          be_done_flag <= 1'b1;
        end else begin
          read_counter_branch <= read_counter_branch + 1'b1;
        end

      end else begin
        branch_buffer_load[1] <= 1'b0;
        read_counter_branch <= 0;
      end
      
    end
  
    // branch 7
    if (model_end_counter == 43) begin
      branch_counter <= 2;

      if (be_done_flag) begin
        read_addr_bias[2] <= read_counter_branch[(w-1):2] + (read_counter_branch[1:0] << s); // 相当于 (cnt[1:0] << 7)
        branch_buffer_load[2] <= 1'b1;// turn on this read enable

        // 计数器自增，超过 511 则回0
        if (read_counter_branch == (buffer_depth - 1)) begin
          read_counter_branch <= 0;
          be_done_flag <= 1'b0;
        end else begin
          read_counter_branch <= read_counter_branch + 1'b1;
        end

      end else begin
        branch_buffer_load[2] <= 1'b0;
        read_counter_branch <= 0;
      end
    end
      
    // branch 8
    if (model_end_counter == 50) begin
      branch_counter <= 3;

      if (!be_done_flag) begin
        read_addr_bias[3] <= read_counter_branch[(w-1):2] + (read_counter_branch[1:0] << s); // 相当于 (cnt[1:0] << 7)
        branch_buffer_load[3] <= 1'b1;// turn on this read enable

        // 计数器自增，超过 511 则回0
        if (read_counter_branch == (buffer_depth - 1)) begin
          read_counter_branch <= 0;
          be_done_flag <= 1'b1;
        end else begin
          read_counter_branch <= read_counter_branch + 1'b1;
        end

      end else begin
        branch_buffer_load[3] <= 1'b0;
        read_counter_branch <= 0;
      end      
    end

  end
end


// buffer input control
reg  [16-1:0]                                          axi_input_counter;
reg                                                 axi_buffer_vld [be_parallelism-1:0];
reg  [(2*bu_parallelism)*(data_width*2)-1:0]        axi_buffer_dat ;

// data buffer write control
// axi to buffer control
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    axi_input_counter <= 0;
    axi_buffer_dat    <= 0;
    axi_buffer_vld[0] <= 1'b0;
    axi_buffer_vld[1] <= 1'b0;
    axi_buffer_vld[2] <= 1'b0;
    axi_buffer_vld[3] <= 1'b0;
    write_addr_bias[0] <= 0;
    write_addr_bias[1] <= 0;
    write_addr_bias[2] <= 0;
    write_addr_bias[3] <= 0;
    write_data_depth  <= buffer_depth;
  end else begin

    axi_buffer_dat <= up_axi_parallel_dat;
    // store the original (pow 2) sequence
    if (up_axi_parallel_vld && (axi_input_counter < buffer_depth)) begin

      axi_buffer_vld[0] <= 1'b1;
      axi_buffer_vld[1] <= 1'b0;
      axi_buffer_vld[2] <= 1'b0;
      axi_buffer_vld[3] <= 1'b0;

    end
    // store (pow 4) sequence
    else if (up_axi_parallel_vld && (axi_input_counter < (buffer_depth*2))) begin

      axi_buffer_vld[0] <= 1'b0;
      axi_buffer_vld[1] <= 1'b1;
      axi_buffer_vld[2] <= 1'b0;
      axi_buffer_vld[3] <= 1'b0;

    end
    // store the (pow 8) sequence
    else if (up_axi_parallel_vld && (axi_input_counter < (buffer_depth*3))) begin

      axi_buffer_vld[0] <= 1'b0;
      axi_buffer_vld[1] <= 1'b0;
      axi_buffer_vld[2] <= 1'b1;
      axi_buffer_vld[3] <= 1'b0;

    end
    // store the (pow 6) sequence
    else if (up_axi_parallel_vld && (axi_input_counter < (buffer_depth*4))) begin

      axi_buffer_vld[0] <= 1'b0;
      axi_buffer_vld[1] <= 1'b0;
      axi_buffer_vld[2] <= 1'b0;
      axi_buffer_vld[3] <= 1'b1;

    end
    else begin

      axi_buffer_vld[0] <= 1'b0;
      axi_buffer_vld[1] <= 1'b0;
      axi_buffer_vld[2] <= 1'b0;
      axi_buffer_vld[3] <= 1'b0;

    end
    //
    if (reset_all) begin
      axi_input_counter <= 0;
    end
    else if (up_axi_parallel_vld) begin
      axi_input_counter <= axi_input_counter + 1;
    end else begin
      axi_input_counter <= axi_input_counter;
    end

  end
end


// 新增一个寄存器级用于打拍，缓解路径延迟
reg [(2*bu_parallelism)*2*data_width-1:0]       dn_parallel_dats_r [be_parallelism-1:0];
reg                                             dn_parallel_vlds_r [be_parallelism-1:0];

generate
  for(i=0 ; i< be_parallelism ; i=i+1) begin : generate_write_back_reg

    always @(posedge clk) begin
        dn_parallel_dats_r[i] <= dn_parallel_dats[i];  // 原来的 dn_parallel_dats 信号作为源
        dn_parallel_vlds_r[i] <= dn_parallel_vlds_A[i];
    end
  end
endgenerate

//////////   For timing Debug   ////////////
reg  [2:0]     up_buffer_sel_r [be_parallelism-1:0];

generate
  for(i=0 ; i< be_parallelism ; i=i+1) begin : GENERATE_buffer_sel_copy

    always @(posedge clk) begin
      up_buffer_sel_r[i] <=  up_buffer_sel;
    end
  end
endgenerate


// (* RLOC = "X0Y3", HU_SET = "top" *)
generate
  for(i=0 ; i< be_parallelism ; i=i+1) begin : GENERATE_SIG_BUFFER

      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          up_buffer_vld[i] <= 1'b0;
          // up_buffer_dat[i] <= {2*bu_parallelism*2*data_width{1'b0}};
        end else begin
          if (up_buffer_sel_r[i] == FROM_AXI) begin
            up_buffer_vld[i] <= axi_buffer_vld[i];
            up_buffer_dat[i] <= axi_buffer_dat;
          end else if (up_buffer_sel_r[i] == FROM_BU) begin
            up_buffer_vld[i] <= dn_parallel_vlds_r[i];
            up_buffer_dat[i] <= dn_parallel_dats_r[i];
          end else begin
            up_buffer_vld[i] <= 1'b0;
            up_buffer_dat[i] <= up_buffer_dat[i];
          end
        end
      end

    data_buffer # (
      .num_rams      (1),
      .bu_parallelism(bu_parallelism),
      .d             (buffer_depth),
      .data_width    (data_width*2),   // for real and imag
      .MEMORY_PRIMITIVE_TYPE("mixed")
    ) u_branch_buffer (
      .clk(clk),  // common clock for read/write access
      .rst_n(rst_n),
      .buffer_full(),
      .counter_clear(read_counter_clear),

      .write_depth(write_data_depth),
      .din_vld(up_buffer_vld[i]),   // active high write enable
      .din(up_buffer_dat[i]),    // data in
      .write_addr_bias(write_addr_bias[i]),
      .write_done(write_done[i]),   // only last one cycle

      .read_depth(read_data_depth),
      .re(branch_buffer_load[i]),   // active high read enable
      .read_addr_bias(read_addr_bias[i]),
      .dout_vld(dn_buffer_vld[i]),
      .dout(dn_buffer_dat[i])     // data out
    );
  end
endgenerate

// =========================================================================== //
// ABS -> Maxpool -> Expansion -> Packaging -> NN
// =========================================================================== //

reg [2*bu_parallelism*2*data_width-1 : 0]      up_abs_dat_r;
reg                                            up_abs_vld_r;

always @(posedge clk) begin

  up_abs_dat_r <= dn_buffer_dat[branch_counter];
  up_abs_vld_r <= dn_buffer_vld[branch_counter];
end


// (* RLOC = "X1Y2", HU_SET = "top" *)
buffer_to_NN # (
  .data_width     (data_width),          // Width of each data element
  .bu_parallelism (bu_parallelism),       // Branch unit parallelism
  .be_parallelism (be_parallelism),       // Backend parallelism
  .MP_size        (8),              // MaxPool window size
  .exp            (8),                   // Expansion factor
  .N              (4)
) u_buffer_to_NN (
  .clk(clk),
  .rst_n(rst_n),

  .up_abs_dat(up_abs_dat_r),
  .up_abs_vld(up_abs_vld_r),

  .dn_pkg_dat(dn_pkg_dat_r),
  .dn_pkg_vld(dn_pkg_vld)
);

generate
  for(i=0 ; i< be_parallelism ; i=i+1) begin : GENERATE_buffer_pkg
    assign dn_pkg_dat[i] = dn_pkg_dat_r[(i+1)*(2*data_width*2*bu_parallelism)-1 : i*(2*data_width*2*bu_parallelism)];
  end
endgenerate


// =========================================================================== //
// Generate Dn Wiring
// =========================================================================== //

  // 内部状态寄存器：标记在本轮 enable 周期内是否已产生过输出
  reg triggered;

  // 时序逻辑：复位、清零以及首次检测
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // 异步复位时清零
      triggered <= 1'b0;
    end
    else if (!output_enable) begin
      // enable 拉低时重置状态，准备下一轮检测
      triggered <= 1'b0;
    end
    else if (dn_parallel_vlds_A[0] && !triggered) begin
      // enable 高且遇到首个 vld，将状态置位
      triggered <= 1'b1;
    end
    // 否则保持触发器原值，无需额外赋值
  end


assign dn_parallel_dat_A = dn_parallel_dats_A;
assign dn_parallel_dat_B = dn_parallel_dats_B;

assign dn_parallel_vld_A = output_enable & dn_parallel_vlds_A[0] & !triggered; 
assign dn_parallel_vld_B = 1'b0; 

endmodule
