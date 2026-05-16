

module MaxPoolExpansion #(
  parameter MP_size   = 8,    // MP_sizeaxPool窗口大小
  parameter N         = 4,    // 并行度
  parameter dw        = 16,    // 数据位宽
  parameter exp       = 8     // 扩展倍数
) (
  input  wire                         clk,
  input  wire                         rst_n,        // 复位（可选）
  input  wire                         input_vld,    // 输入有效信号
  input  wire [MP_size * N * dw-1:0]  data_in,
  output reg                          output_vld,   // 输出有效信号
  output reg  [exp * N * dw-1:0]      data_out
);

// ========== 保存经过最大池化后的N个数 ==========
reg [dw-1:0] max_values [N-1:0];

// ========== MP_sizeaxPool处理逻辑 ==========
// 窗口分割与最大值计算（组合逻辑）
wire [dw-1:0] window_data [N-1:0][MP_size-1:0];
genvar i, j;

generate 
  for (i = 0; i < N; i = i + 1) begin : window_split

    for (j = 0; j < MP_size; j = j + 1) begin : element_assign
      assign window_data[i][j] = data_in[(i*MP_size + j)*dw +: dw];
    end
    
    integer l;
    always @(*) begin
      max_values[i] = window_data[i][0];
      for (l = 1; l < MP_size; l = l + 1) begin
        if (window_data[i][l] > max_values[i]) begin
          max_values[i] = window_data[i][l];
        end
      end
    end
  end
endgenerate

integer k, e;
// ========== 数据扩展与输出 ==========
// 原来的扩展逻辑：对每个通道，将结果依次分散在 data_out 的各个位置
// 修改后：对每个通道，将该通道的结果连续复制 exp 次

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    data_out   <= 0;
    output_vld <= 0;
  end else begin
    for (k = 0; k < N; k = k + 1) begin
      for (e = 0; e < exp; e = e + 1) begin
        // 新的索引计算：先按通道排序，每个通道连续 exp 个数据
        data_out[((k * exp) + e) * dw +: dw] <= max_values[k];
      end
    end
    output_vld <= input_vld;
  end
end

endmodule



// module MaxPoolExpansion_pipelined #(
//     parameter MP_size = 8,   // MaxPool窗口大小（例如8）
//     parameter N       = 4,   // 并行通道数（例如4）
//     parameter dw      = 16,  // 数据位宽（如半精度浮点16位）
//     parameter exp     = 8    // 扩展倍数（输出复制次数）
// )(
//     input  wire                          clk,
//     input  wire                          rst_n,
//     input  wire                          input_vld,                      // 输入有效信号
//     input  wire [MP_size * N * dw - 1:0] data_in,                        // 输入数据，总宽度=8*4*16=512bit
//     output reg                           output_vld,                     // 输出有效信号
//     output reg  [exp * N * dw - 1:0]     data_out                        // 输出数据，总宽度=8*4*16=512bit
// );

//     // **流水线有效信号寄存器**
//     reg stage1_valid, stage2_valid, stage3_valid;

//     // **流水线中间数据寄存器**
//     // 第1级比较后的值：每通道产生4个16位结果
//     reg [dw-1:0] stage1_val [N-1:0][(MP_size/2)-1:0];
//     // 第2级比较后的值：每通道产生2个16位结果
//     reg [dw-1:0] stage2_val [N-1:0][(MP_size/4)-1:0];
//     // （第3级直接将结果扩展后写入data_out，无需单独stage3_val）

//     // **比较器输出标志（8位，只有最低位有效）**
//     wire [7:0] comp1_flag [N-1:0][(MP_size/2)-1:0];  // 第1级4个比较器输出
//     wire [7:0] comp2_flag [N-1:0][(MP_size/4)-1:0];  // 第2级2个比较器输出
//     wire [7:0] comp3_flag [N-1:0];                  // 第3级1个比较器输出

//     // ========== 第1级比较：8进4（每对比较） ==========
//     genvar i, j;
//     generate 
//       for (i = 0; i < N; i = i + 1) begin : GEN_STAGE1
//         for (j = 0; j < MP_size/2; j = j + 1) begin : GEN_CMP1
//           fp_half_comp cmp1_inst (
//             .s_axis_a_tvalid(input_vld),
//             .s_axis_a_tdata( data_in[((i*MP_size)+(2*j)  )*dw +: dw] ),  // 对应A操作数
//             .s_axis_b_tvalid(input_vld),
//             .s_axis_b_tdata( data_in[((i*MP_size)+(2*j+1))*dw +: dw] ),  // 对应B操作数
//             .m_axis_result_tvalid(),        // 此例中未使用
//             .m_axis_result_tdata( comp1_flag[i][j] )  // 8位输出，仅bit0有意义
//           );
//         end
//       end
//       // ========== 第2级比较：4进2 ==========
//       for (i = 0; i < N; i = i + 1) begin : GEN_STAGE2
//         for (j = 0; j < MP_size/4; j = j + 1) begin : GEN_CMP2
//           fp_half_comp cmp2_inst (
//             .s_axis_a_tvalid(stage1_valid),
//             .s_axis_a_tdata( stage1_val[i][2*j]   ),  // 来自第1级寄存的比较结果A
//             .s_axis_b_tvalid(stage1_valid),
//             .s_axis_b_tdata( stage1_val[i][2*j+1] ),  // 来自第1级寄存的比较结果B
//             .m_axis_result_tvalid(),
//             .m_axis_result_tdata( comp2_flag[i][j] )
//           );
//         end
//       end
//       // ========== 第3级比较：2进1 ==========
//       for (i = 0; i < N; i = i + 1) begin : GEN_STAGE3
//         fp_half_comp cmp3_inst (
//           .s_axis_a_tvalid(stage2_valid),
//           .s_axis_a_tdata( stage2_val[i][0] ),   // 来自第2级寄存结果A
//           .s_axis_b_tvalid(stage2_valid),
//           .s_axis_b_tdata( stage2_val[i][1] ),   // 来自第2级寄存结果B
//           .m_axis_result_tvalid(),
//           .m_axis_result_tdata( comp3_flag[i] )
//         );
//       end
//     endgenerate

//     // ========== 时序逻辑：寄存各级结果和有效信号 ==========
//     integer m, k;
//     always @(posedge clk or negedge rst_n) begin
//       if (!rst_n) begin
//         // 异步复位：清空所有流水线寄存器
//         stage1_valid <= 1'b0;
//         stage2_valid <= 1'b0;
//         stage3_valid <= 1'b0;
//         output_vld   <= 1'b0;
//         for (m = 0; m < N; m = m + 1) begin
//           for (k = 0; k < MP_size/2; k = k + 1)
//             stage1_val[m][k] <= {dw{1'b0}};
//           for (k = 0; k < MP_size/4; k = k + 1)
//             stage2_val[m][k] <= {dw{1'b0}};
//         end
//         data_out <= {exp*N*dw{1'b0}};
//       end else begin
//         // **有效信号流水线推进**
//         stage1_valid <= input_vld;
//         stage2_valid <= stage1_valid;
//         stage3_valid <= stage2_valid;
//         output_vld   <= stage3_valid;
//         // **第1级寄存：保存每对比较的大者（每通道4个）**
//         if (input_vld) begin
//           for (m = 0; m < N; m = m + 1) begin
//             // 对于每个通道m的8个输入，按顺序两两比较：
//             stage1_val[m][0] <= comp1_flag[m][0][0] ? 
//                                 data_in[((m*MP_size)+0)*dw +: dw] :  // A>=B选A
//                                 data_in[((m*MP_size)+1)*dw +: dw];   // A<B选B
//             stage1_val[m][1] <= comp1_flag[m][1][0] ?
//                                 data_in[((m*MP_size)+2)*dw +: dw] :
//                                 data_in[((m*MP_size)+3)*dw +: dw];
//             stage1_val[m][2] <= comp1_flag[m][2][0] ?
//                                 data_in[((m*MP_size)+4)*dw +: dw] :
//                                 data_in[((m*MP_size)+5)*dw +: dw];
//             stage1_val[m][3] <= comp1_flag[m][3][0] ?
//                                 data_in[((m*MP_size)+6)*dw +: dw] :
//                                 data_in[((m*MP_size)+7)*dw +: dw];
//           end
//         end
//         // **第2级寄存：保存上一层比较结果的大者（每通道2个）**
//         if (stage1_valid) begin
//           for (m = 0; m < N; m = m + 1) begin
//             stage2_val[m][0] <= comp2_flag[m][0][0] ?
//                                 stage1_val[m][0] : stage1_val[m][1];
//             stage2_val[m][1] <= comp2_flag[m][1][0] ?
//                                 stage1_val[m][2] : stage1_val[m][3];
//           end
//         end
//         // **第3级输出：将最大值扩展exp份并输出（每通道1→8）**
//         if (stage2_valid) begin
//           for (m = 0; m < N; m = m + 1) begin
//             for (k = 0; k < exp; k = k + 1) begin
//               data_out[(m*exp + k)*dw +: dw] <= comp3_flag[m][0] ? 
//                                                 stage2_val[m][0] : stage2_val[m][1];
//             end
//           end
//         end
//       end
//     end
// endmodule



module index_generator # (
  parameter BU          = 32,           // 2 * bu_parallel
  parameter DEPTH       = 1024,      // Depth parameter (power of 2)
  parameter BE          = 4,             // BE parameter (power of 2)
  parameter data_width  = 16,
  parameter BU_BITS     = $clog2(BU)
) (
  input  wire                         clk,      // Clock input
  input  wire                         rst_n,    // Active-low reset
  input  wire                         vld,      // Valid input signal
  input  wire  [data_width*BU-1:0]    data_in,      //  signal

  output wire                         vld_o,
  output wire  [BU_BITS-1:0]          index,     // Final index output
  output wire  [data_width*BU-1:0]    data_out      //  signal
);

  // Calculate depth_per_be for cleaner code (DEPTH/BE)
  localparam DEPTH_PER_BE = DEPTH / BE;   // 256
  
  // Calculate bit positions for efficient bit manipulation
  localparam BE_BITS = $clog2(BE);                  // Number of bits needed to represent BE
  localparam DEPTH_PER_BE_BITS = $clog2(DEPTH_PER_BE); // Number of bits needed to represent DEPTH_PER_BE

  // Internal registers
  reg [16-1:0]        reg_counter;      // Base register counter
  reg [32-1:0]        cnt;              // BU multiplier counter
  // reg                 flag;             // Flag register (0,0,0,0,1,1,1,1,...)

  reg                 vld_r0;            // Registered valid signal
  reg                 vld_r1;            // Registered valid signal
  // reg                 vld_r2;            // Registered valid signal
  
  reg [16-1:0]        cnt_r;            // Pipelined cnt
  // reg                 flag_r;           // Pipelined flag
  reg [data_width*BU-1:0]    data_r0;
  reg [data_width*BU-1:0]    data_r1;
  // reg [data_width*BU-1:0]    data_r2;


  // Implementation of reg_counter logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_counter <= 16'd0;
      vld_r0      <= 1'b0;
      data_r0     <= 0;
    end else begin
      vld_r0 <= vld;
      data_r0 <= data_in;

      if (vld) begin
        // Check if we've reached the last index pattern (DEPTH - 1)
        if (reg_counter == DEPTH - 1) begin
          reg_counter <= 16'd0;
        end else begin
          reg_counter <= reg_counter + 1'b1;
        end
      end else begin
        reg_counter <= reg_counter;
      end

    end
  end
  
  // Pipeline stage 1: Calculate the core values using bit manipulation
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      vld_r1 <= 0;
      cnt    <= 0;
      // flag   <= 0;
      data_r1 <= 0;
    end else begin
      vld_r1 <= vld_r0;
      data_r1 <= data_r0;
      // Calculate using bit manipulation:
      // BE offset = (reg_counter % BE) * DEPTH_PER_BE = (reg_counter & (BE-1)) << DEPTH_PER_BE_BITS
      // Counter component = (reg_counter / BE) = (reg_counter >> BE_BITS)
      cnt <= (((reg_counter & (BE-1)) << DEPTH_PER_BE_BITS) | (reg_counter >> BE_BITS)) << BU_BITS;
      // flag <= (reg_counter >> BE_BITS) & 1'b1;
    end
  end
  

  reg   [16-1:0]   temp;

    integer j;
    always @(*) begin
        temp = cnt[BU_BITS-1:0];
        for (j=0 ; j<(16 - BU_BITS) ; j=j+1) begin
            temp = temp + cnt[BU_BITS+j];
        end
    end

  // Pipeline stage 2: Calculate temp_index based on cnt
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_r  <= 0;
      // flag_r <= 0;
      // vld_r2 <= 0;
      // data_r2 <= 0;
    end else begin
      // vld_r2 <= vld_r1;
      // data_r2 <= data_r1;
      cnt_r <= temp;
      // flag_r <= flag;
    end
  end
  
  assign index = cnt_r[BU_BITS-1:0];
  assign data_out = data_r1;
  assign vld_o = vld_r1;

endmodule



module buffer_to_NN # (
  parameter data_width     = 16,          // Width of each data element
  parameter bu_parallelism = 16,          // Branch unit parallelism
  parameter be_parallelism = 4,           // Backend parallelism
  parameter MP_size        = 8,           // MaxPool window size
  parameter exp            = 8,           // Expansion factor
  parameter N              = 4
) (
  // Clock and reset
  input  wire                                               clk,
  input  wire                                               rst_n,
  // Input interface from buffer
  input  wire [2*data_width*2*bu_parallelism-1:0]           up_abs_dat,
  input  wire                                               up_abs_vld,
  // Output interface - final processed data for neural network
  output wire [2*data_width*2*bu_parallelism*be_parallelism-1:0]    dn_pkg_dat,
  output reg                                                        dn_pkg_vld
);

  // Internal signals
  wire  [2*bu_parallelism-1:0]                   dn_abs_vld;
  wire [data_width*2*bu_parallelism-1:0]         dn_abs_dat;

  // Generate complex absolute value calculation pipelines
  genvar i, j;
  generate
    for (j = 0; j < 2*bu_parallelism; j = j + 1) begin : GEN_PIPELINE
      // Instantiate sif_complex_abs_fxp with registered signals as inputs
      sif_complex_abs_fp u_cplx_abs (
        .clk(clk),
        .rst_n(rst_n),
        .up_i(up_abs_dat[(2*data_width*j + data_width-1) : (2*data_width*j)]),
        .up_i_vld(up_abs_vld),
        .up_q(up_abs_dat[(2*data_width*j + 2*data_width-1) : (2*data_width*j + data_width)]),
        .up_q_vld(up_abs_vld),
        .dn_dat(dn_abs_dat[(data_width*j + data_width-1) : (data_width*j)]),
        .dn_vld(dn_abs_vld[j])
      );
    end
  endgenerate

  // barrel shifter for NN input
  localparam DEPTH     = 32768/(2*bu_parallelism);
  localparam BU_BITS   = $clog2(2*bu_parallelism);
  wire                                     up_shift_vld;
  wire [BU_BITS-1:0]                       index;
  wire [2*bu_parallelism*data_width-1:0]   up_shift_dat;

  index_generator # (
      .BU          (2*bu_parallelism),           // 2 * bu_parallel
      .DEPTH       (DEPTH),                       // Depth parameter (power of 2)
      .BE          (be_parallelism),             // BE parameter (power of 2)
      .data_width  (data_width)
  ) u_NN_in_shift (
      .clk(clk),
      .rst_n(rst_n),
      .vld(dn_abs_vld[0]),
      .data_in(dn_abs_dat),
      .vld_o(up_shift_vld),
      .index(index),
      .data_out(up_shift_dat)
  );

  // barrel shifter for NN input data grouping
  wire [2*bu_parallelism-1:0]    data_block [data_width-1:0];
  wire [2*bu_parallelism-1:0]    data_shift [data_width-1:0];
  wire [2*bu_parallelism*data_width-1:0]   dn_shift_dat;
  reg  [2*bu_parallelism*data_width-1:0]   dn_shift_dat_r;
  reg                                      dn_shift_vld_r;
  
  generate
    for (i = 0; i < (2*bu_parallelism); i = i + 1) begin
      for (j = 0; j < data_width; j = j + 1) begin
        assign data_block[j][i] = up_shift_dat[j + data_width*i];
        assign dn_shift_dat[j + data_width*i] = data_shift[j][i];
      end
    end
  endgenerate

  generate
    for (i = 0; i < data_width; i = i + 1) begin
      read_rotate #(
        .data_length(2*bu_parallelism)
      ) u_NN_read_rotate (
        .shift(index),
        .up_data(data_block[i]),
        .dn_data(data_shift[i])
      );
    end
  endgenerate

  // pipeline for timing
  always @(posedge clk) begin
    dn_shift_dat_r <= dn_shift_dat;
    dn_shift_vld_r <= up_shift_vld;
  end


  wire [data_width*2*bu_parallelism-1:0]         dn_abs_exp_dat;
  wire                                           dn_abs_exp_vld;

  // Max pool expansion module instantiation
  MaxPoolExpansion # (
    .MP_size (MP_size),   // MaxPool window size
    .N       (N),         // Parallelism degree
    .dw      (data_width),// Data width
    .exp     (exp)        // Expansion factor
  ) u_mp_abs_exp (
    .clk      (clk),
    .rst_n    (rst_n),
    .input_vld(dn_shift_vld_r),
    .data_in  (dn_shift_dat_r),
    .output_vld(dn_abs_exp_vld),
    .data_out (dn_abs_exp_dat)
  );

  // Package counter logic
  reg  [2*bu_parallelism*data_width-1:0] dn_pkg_dat_r [be_parallelism-1:0];
  reg  [1:0]                           pkg_counter;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pkg_counter <= 0;
      dn_pkg_vld  <= 0;
    end else begin
      if (dn_abs_exp_vld) begin
        pkg_counter <= pkg_counter + 1;
      end
      dn_pkg_dat_r[pkg_counter] <= dn_abs_exp_dat;
      if (pkg_counter == be_parallelism-1)
        dn_pkg_vld <= 1'b1;
      else
        dn_pkg_vld <= 1'b0;
    end
  end

  // Data restructuring for NN input
  wire [2*data_width*2*bu_parallelism-1:0] dn_pkg_dat_r_2d [be_parallelism-1:0];
  generate
    for (i = 0; i < be_parallelism; i = i + 1) begin
      for (j = 0; j < 2*bu_parallelism; j = j + 1) begin
        assign dn_pkg_dat_r_2d[i][(2*data_width*j + data_width-1) : (2*data_width*j)] = 
            dn_pkg_dat_r[i][(data_width*j + data_width-1) : (data_width*j)];
        assign dn_pkg_dat_r_2d[i][(2*data_width*j + 2*data_width-1) : (2*data_width*j + data_width)] = 0;
      end
    end
  endgenerate

  // Flatten the output for the 1D port
  generate
    for (i = 0; i < be_parallelism; i = i + 1) begin : FLATTEN_OUTPUT
      assign dn_pkg_dat[(i+1)* (2*data_width*2*bu_parallelism)-1 : i*(2*data_width*2*bu_parallelism)] 
        = dn_pkg_dat_r_2d[i];
    end
  endgenerate

endmodule
