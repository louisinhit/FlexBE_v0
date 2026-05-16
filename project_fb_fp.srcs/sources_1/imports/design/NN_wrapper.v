

module NN_wrapper_axi # (
    // Engine Spec
    parameter data_width     = 16,
    parameter be_parallelism = 4,
    parameter bu_parallelism = 16,
    parameter parallelism_per_control = 2,
    
    parameter latency_mul    = 2,
    parameter latency_add    = 2,
    parameter caddsub_delay  = 2,

    // User parameters ends
    // Parameters of Axi Slave Bus Interface S00_AXIS
    // 1024
    parameter integer C_S00_AXIS_TDATA_WIDTH	= 4 * data_width * bu_parallelism,
    // Parameters of Axi Master Bus Interface M00_AXIS
    // 2048
    parameter integer C_M00_AXIS_TDATA_WIDTH	= bu_parallelism * data_width * be_parallelism * 2
)	(
    // Ports of Axi Slave Bus Interface S00_AXIS for the configuration
    input wire  s00_axis_aclk,
    input wire  s00_axis_aresetn,
    output wire  s00_axis_tready,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] s00_axis_tdata,
    // input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] s00_axis_tkeep,
    input wire  s00_axis_tlast,
    input wire  s00_axis_tvalid,

    // Ports of Axi Master Bus Interface M00_AXIS
    input wire  m00_axis_aclk,
    input wire  m00_axis_aresetn,
    output wire  m00_axis_tvalid,
    output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
    // output wire [(C_M00_AXIS_TDATA_WIDTH/8)-1 : 0] m00_axis_tkeep,
    output wire  m00_axis_tlast,
    input wire  m00_axis_tready
);

    wire                   sys_clk;
    wire                   rst_n;

    assign sys_clk = s00_axis_aclk;
    assign rst_n   = s00_axis_aresetn;

    // localparam up_tready = 1'b1;
    localparam    DEPTH   = 4096;  // each batch needs 4096 vld cycles.
    localparam    ADDR_W  = $clog2(DEPTH);
    
    reg          s_rdy;
    assign s00_axis_tready = s_rdy;
    

    // axi 事务管理
    reg                                m00_axis_tvalid_w;
    reg [C_M00_AXIS_TDATA_WIDTH-1:0]   m00_axis_tdata_w;
    reg                                m00_axis_tlast_w;

    reg                                axi_input_vld;
    reg                                axi_weight_vld;
    reg [C_S00_AXIS_TDATA_WIDTH-1:0]   axi_input_dat;  // input 32k, square later  
    
    // 状态控制
    reg                    axi_count;
    reg   [1:0]            state;
    reg   [31:0]           wgt_cnt;
    reg [ADDR_W-1:0]       cnt_d;


    // s00 ready control
    always @(posedge sys_clk or negedge rst_n) begin
      if (!rst_n) begin
        s_rdy  <= 1'b1;
        cnt_d    <= 0;
      end else begin

        if (axi_count && s00_axis_tvalid && s_rdy) begin
          cnt_d <= cnt_d + 1'b1;
        end else begin
          cnt_d <= cnt_d;
        end

        if ((cnt_d == (DEPTH-1)) && s00_axis_tvalid)  begin
          s_rdy <= 0;
        end
        else if (nn_tlast_r) begin
          s_rdy <= 1'b1;
        end else begin
          s_rdy <= s_rdy;
        end
      end
    end
  

    // 输入控制
    always @(posedge sys_clk or negedge rst_n) begin
      if (!rst_n) begin
        axi_count      <= 0;
        axi_weight_vld <= 0;
        axi_input_vld  <= 0;
        axi_input_dat <= 0;
      end else begin

        if (s00_axis_tlast && s00_axis_tvalid) begin
          axi_count <= 1'b1;
        end
        
        if (!axi_count) begin
          axi_weight_vld <= s00_axis_tvalid & s_rdy;
          axi_input_vld  <= 0;
        end else begin
          axi_weight_vld <= 0;
          axi_input_vld  <= s00_axis_tvalid & s_rdy;
        end

        axi_input_dat <= s00_axis_tdata;
      end
    end
  
    
    // 输出控制
    always @(posedge sys_clk or negedge rst_n) begin
      if (!rst_n) begin
        wgt_cnt   <= 0;
        state     <= 0;
        m00_axis_tvalid_w <= 0;
        m00_axis_tdata_w  <= 0;
        m00_axis_tlast_w  <= 0;
      end else begin

        if (!axi_count) begin

          if (s00_axis_tvalid)
            wgt_cnt <= wgt_cnt + 1'b1;
          else
            wgt_cnt <= wgt_cnt;

        end else if (axi_count && (state == 0)) begin
          m00_axis_tvalid_w <= 1'b1;
          m00_axis_tdata_w <= wgt_cnt;
          m00_axis_tlast_w <= 1'b1;
          state <= 2'b01;
        end
        else if (state == 2'b01) begin
          state <= 2'b11;
          m00_axis_tvalid_w <= 0;
          m00_axis_tdata_w <= 0;
          m00_axis_tlast_w <= 0;
        end
        else if ((state == 2'b11) && s00_axis_tlast && s00_axis_tvalid) begin  // 等待所有batch的数据传完
          state <= 2'b10;
        end
        else if ((state == 2'b10) && s00_axis_tvalid) begin  // 等待所有batch的数据传完
          state <= 2'b11;
        end
        else  begin
          state <= state; // 保持 2'b11 状态  开始分类器部分
          m00_axis_tvalid_w <= 0;
          m00_axis_tdata_w <= 0;
          m00_axis_tlast_w <= 0;
        end
      end
    end


  reg                                                        nn_tlast_r;
  reg                                                        dn_parallel_vld; 
  reg   [(2*bu_parallelism)*data_width*be_parallelism-1:0]   dn_parallel_dat; // real
  
  wire                                                       dn_parallel_vlds_A; 
  wire  [(2*bu_parallelism)*data_width*be_parallelism-1:0]   dn_parallel_dats_A; // real
  wire                                                       nn_tlast;


  always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
      nn_tlast_r      <= 0;  // For timing
      dn_parallel_vld <= 0;
      dn_parallel_dat <= 0;
    end else begin
      nn_tlast_r      <= nn_tlast & dn_parallel_vlds_A;  // For timing
      dn_parallel_vld <= dn_parallel_vlds_A;
      dn_parallel_dat <= dn_parallel_dats_A;
    end
  end


  assign m00_axis_tdata  = (state == 2'b01) ? m00_axis_tdata_w  : dn_parallel_dat;
  assign m00_axis_tvalid = (state == 2'b01) ? m00_axis_tvalid_w : dn_parallel_vld; 

  assign m00_axis_tlast  = (state == 2'b01) ? m00_axis_tlast_w  : (state == 2'b10) ? nn_tlast_r  : 0;


  // =========================================================================== //
  // Instantiate Butterfly Process
  // =========================================================================== //


  NN_top # (
    .data_width(data_width),
    .be_parallelism(be_parallelism),
    .bu_parallelism(bu_parallelism),
    .parallelism_per_control(parallelism_per_control),
    .latency_add(latency_add),
    .latency_mul(latency_mul),
    .caddsub_delay(caddsub_delay)
  ) u_nn_top (
    .clk(sys_clk),
    .rst_n(rst_n),
    //===================weight data=======================//
    .up_weight_dat(axi_input_dat),
    .up_weight_vld(axi_weight_vld),
    //=================input and output=====================//
    .up_axi_serial_vld(1'b0),
    .up_axi_serial_dat(/* unused */),
    .up_axi_parallel_vld(axi_input_vld),
    .up_axi_parallel_dat(axi_input_dat),
    .up_rdy(),

    // Port A
    // down stream data output for FFT
    // output wire                        dn_parallel_vld_A, 
    // output wire  [(2*bu_parallelism)*data_width*be_parallelism-1:0]      dn_parallel_dat_A, // real
    .dn_parallel_vld_A(dn_parallel_vlds_A),
    .dn_parallel_dat_A(dn_parallel_dats_A),   //  2048 width for pu=16
    .dn_parallel_rdy_A(1'b1),

    // Port B
    // down stream data output for FFT
    // output wire                        dn_parallel_vld_B, 
    // output wire  [(2*bu_parallelism)*data_width*be_parallelism-1:0]      dn_parallel_dat_B, // complex
    .dn_parallel_vld_B(),
    .dn_parallel_dat_B(),
    .dn_parallel_rdy_B(1'b1),

    .last_branch(nn_tlast)
  );



endmodule

