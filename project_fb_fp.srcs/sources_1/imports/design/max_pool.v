
module max_pool #(
    parameter N         = 32,   // Number of columns
    parameter BIT_WIDTH = 16    // Bit width of each element
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     valid_in,
    input  wire [N*BIT_WIDTH-1:0]   data_in,
    input  wire [3:0]               max_pool_size,  // 改为输入

    output reg                      valid_out,
    output wire [N*BIT_WIDTH-1:0]   data_out
);

    // count 位宽与 max_pool_size 一致
    reg [3:0]                count;
    // 拆分为 N 路数据
    wire [BIT_WIDTH-1:0]     up_dats [0:N-1];
    reg  [BIT_WIDTH-1:0]     max_pool_reg [0:N-1];

    wire    [7:0]            larger [0:N-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count     <= 0;
            valid_out <= 1'b0;
        end else begin
            if (valid_in && (count == (max_pool_size - 1)))
              count <= 0;
            else if (valid_in)
              count <= count + 1;
            else
              count <= count;

            // 达到 max_pool_size 个周期后输出一个有效脉冲
            if (count == (max_pool_size - 1))
                valid_out <= 1'b1;
            else
                valid_out <= 1'b0;
        end
    end

    genvar j;
    generate
      for (j = 0; j < N; j = j + 1) begin : max_computation

        // 拆出实部（或唯一通道）数据
        assign up_dats[j] = data_in[j*BIT_WIDTH +: BIT_WIDTH];

          fp_half_comp  u_sc_mp_cmp  (
            .s_axis_a_tvalid      (valid_in),
            .s_axis_a_tdata       (up_dats[j]),  // 对应A操作数
            .s_axis_b_tvalid      (valid_in),
            .s_axis_b_tdata       (max_pool_reg[j]),  // 对应B操作数
            .m_axis_result_tvalid (),        // 此例中未使用
            .m_axis_result_tdata  (larger[j])  // 8位输出，仅bit0有意义
          );


        always @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            max_pool_reg[j] <= {BIT_WIDTH{1'b0}};
          end else begin
            // 第一次进数时，直接赋初值
            if (valid_in && count == 0)
              max_pool_reg[j] <= up_dats[j];
            // 其后不断比较取大
            else if (valid_in && larger[j][0])
              max_pool_reg[j] <= up_dats[j];
          end
        end

        // 将当前最大值输出
        assign data_out[j*BIT_WIDTH +: BIT_WIDTH] = max_pool_reg[j];
      end
    endgenerate

endmodule




// 封装 SC Add + ReLU + Maxpool 功能模块
module sc_relu_maxpool #(
    parameter data_width     = 16,
    parameter bu_parallelism = 4
)(
    input  wire                                 clk,
    input  wire                                 rst_n,

    input  wire                                 dn_parallel_vld,    // 来自 dn_parallel_vlds_A_r[i]
    input  wire [(2*bu_parallelism)*data_width-1:0] dn_parallel_dat,  // 来自 dn_parallel_dats_A_r[i]
    input  wire                                 dn_sc_fifo_vld,     // 来自 FIFO 输出
    input  wire [(2*bu_parallelism)*data_width-1:0] dn_sc_fifo_dat,   // 来自 FIFO 输出

    // 新增：动态可配置的池化大小
    input  wire [3:0]                           max_pool_size,

    output wire                                  dn_sc_mp_vld,
    output wire [(2*bu_parallelism)*data_width-1:0] dn_sc_mp_dat
);

    // === SC Add + ReLU 部分（保持不变） ===
    wire [2*bu_parallelism-1:0]                dn_sc_add_vlds;
    wire [data_width*2*bu_parallelism-1:0]     dn_sc_add_dats;

    genvar j;
    generate
      for (j = 0; j < 2*bu_parallelism; j = j + 1) begin : GEN_SC_ADD
        wire [data_width-1:0] add_sc_dat;
        wire                  add_sc_vld;

        sif_add_half  u_sif_sc_add (
          .clk   (clk),
          .rst_n (rst_n),
          .A_vld (dn_parallel_vld),
          .A_dat (dn_parallel_dat[j*data_width +: data_width]),
          .A_rdy (),
          .B_vld (dn_sc_fifo_vld),
          .B_dat (dn_sc_fifo_dat [j*data_width +: data_width]),
          .B_rdy (),
          .S_vld (add_sc_vld),
          .S_dat (add_sc_dat),
          .S_rdy (1'b1)
        );

        // ReLU 打拍
        reg [data_width-1:0] relu_dat;
        reg                  relu_vld;
        always @(posedge clk) begin
          relu_dat <= add_sc_dat[data_width-1] ? {data_width{1'b0}} : add_sc_dat ;
          relu_vld <= add_sc_vld;
        end

        assign dn_sc_add_dats[j*data_width +: data_width] = relu_dat;
        assign dn_sc_add_vlds[j]                        = relu_vld;
      end
    endgenerate

    reg  [3:0]                       max_pool_size_r;

    // ============  timing     
    always @(posedge clk) begin
        max_pool_size_r <= max_pool_size;
    end

    max_pool #(
      .N        (2*bu_parallelism),
      .BIT_WIDTH(data_width)
    ) u_max_pool (
      .clk            (clk),
      .rst_n          (rst_n),
      .valid_in       (dn_sc_add_vlds[0]),
      .data_in        (dn_sc_add_dats),
      .max_pool_size  (max_pool_size_r),       // 传入动态大小
      .valid_out      (dn_sc_mp_vld),
      .data_out       (dn_sc_mp_dat)
    );

endmodule

