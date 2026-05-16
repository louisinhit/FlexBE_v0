
// Data buffer 
// complex write logic but simple read order

module data_buffer
# (
  parameter num_rams              = 1,
  parameter bu_parallelism        = 32,
  parameter d                     = 512,
  parameter data_width            = 16,
  parameter ADDR_WIDTH            = $clog2(d),
  parameter MEMORY_PRIMITIVE_TYPE = "mixed"
) (
  input                                             clk,  // common clock for read/write access
  input                                             rst_n,
  output  reg                                       buffer_full,
  input                                             counter_clear,

  input [$clog2(d):0]                               write_depth,
  input                                             din_vld,   // active high write enable
  input  [2*bu_parallelism*num_rams*data_width-1:0] din,    // data in
  input  [$clog2(d):0]                              write_addr_bias,
  output  reg                                       write_done,  

  input [$clog2(d):0]                                read_depth,
  input                                              re,   // active high read enable
  input  [$clog2(d):0]                               read_addr_bias,
  output                                             dout_vld,
  output  [2*bu_parallelism*num_rams*data_width-1:0] dout     // data out  
);

genvar i;

wire [bu_parallelism*2*data_width-1:0]   dins      [num_rams-1:0];
wire [bu_parallelism*2*data_width-1:0]   douts     [num_rams-1:0];
wire                                     douts_vld [num_rams-1:0];

reg [16-1:0]                write_counter;

always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    write_counter <= 0;
    write_done <= 0;
  end else begin

    if (write_counter == write_depth) begin
      write_counter <= 0;
      write_done <= 1'b1;
    end
    else if (din_vld) begin
      write_done <= 0;
      write_counter <= write_counter + 1;
    end else begin
      write_counter <= write_counter;
      write_done <= 0;
    end
  end
end

reg [16-1:0]                read_counter;

always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    read_counter <= 0;
  end else begin

    if ((read_counter == (read_depth - 1)) || counter_clear) begin
      read_counter <= 0;
    end
    else if (re && buffer_full) begin
      read_counter <= read_counter + 1;
    end
    else begin
      read_counter <= read_counter;
    end
  end
end

// buffer full register control
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    buffer_full <= 0;
  end else begin

    if (write_done) begin
      buffer_full <= 1;
    end
    else if (read_counter == (read_depth - 1)) begin
      buffer_full <= 0;
    end
  end
end


wire [16-1:0]     write_addr;
wire [16-1:0]     read_addr;

assign write_addr = write_counter + write_addr_bias;
assign read_addr = read_counter + read_addr_bias;

generate  
  for(i=0 ; i<num_rams ; i=i+1) begin

    assign dins[i] = din[ (data_width*2*bu_parallelism)*i + (data_width*2*bu_parallelism) - 1 : (data_width*2*bu_parallelism)*i ];

      data_buffer_top # (
        .w(data_width*2*bu_parallelism),
        .d(d),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MEMORY_PRIMITIVE_TYPE(MEMORY_PRIMITIVE_TYPE)
      ) u_data_buffer_t (
        .clk(clk),  // common clock for read/write access
        .rst_n(rst_n),
        .we(din_vld),   // active high write enable
        .write_addr(write_addr),   // write address
        .din(dins[i]),    // data in
      
        .re(re & buffer_full),   // active high read enable
        .read_addr(read_addr),   // read address
        .dout_vld(douts_vld[i]),
        .dout(douts[i])     // data out
      ); // ram_simple_dual

    assign dout[(2*bu_parallelism*data_width*i + 2*bu_parallelism*data_width - 1):(2*bu_parallelism*data_width*i)] = douts[i];
  end
endgenerate

assign dout_vld = douts_vld[0];

endmodule




module data_buffer_top
#(
   parameter w = 64,
   parameter d = 128,
   parameter ADDR_WIDTH = $clog2(d),
   parameter MEMORY_PRIMITIVE_TYPE = "mixed"
)
(
  input                    clk,     // common clock for read/write access
  input                    rst_n,
  input                    we,      // active high write enable
  input   [$clog2(d)-1:0]  write_addr, 
  input   [w-1:0]          din,     // data in

  input                    re,      // active high read enable
  input   [$clog2(d)-1:0]  read_addr,   // read address
  output                   dout_vld,
  output  [w-1:0]          dout         // data out
);

reg                     dout_vld_r;

always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    dout_vld_r <= 1'b0;
  end else begin
    dout_vld_r <= re;
  end
end

assign dout_vld = dout_vld_r;
  
// using sdpram or spram
   xpm_memory_sdpram #(
      .ADDR_WIDTH_A(ADDR_WIDTH),               // DECIMAL
      .ADDR_WIDTH_B(ADDR_WIDTH),               // DECIMAL
      .AUTO_SLEEP_TIME(0),            // DECIMAL
      .BYTE_WRITE_WIDTH_A(w),        // DECIMAL
      .CASCADE_HEIGHT(0),             // DECIMAL
      .CLOCKING_MODE("common_clock"), // String
      .ECC_MODE("no_ecc"),            // String
      .MEMORY_INIT_FILE("none"),      // String
      .MEMORY_INIT_PARAM("0"),        // String
      .MEMORY_OPTIMIZATION("true"),   // String
      .MEMORY_PRIMITIVE(MEMORY_PRIMITIVE_TYPE),      // String
      .MEMORY_SIZE(w * d),             // DECIMAL
      .MESSAGE_CONTROL(0),            // DECIMAL
      .READ_DATA_WIDTH_B(w),         // DECIMAL
      .READ_LATENCY_B(1),             // DECIMAL
      .READ_RESET_VALUE_B("0"),       // String
      .RST_MODE_A("SYNC"),            // String
      .RST_MODE_B("SYNC"),            // String
      .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
      .USE_MEM_INIT(0),               // DECIMAL
      .WAKEUP_TIME("disable_sleep"),  // String
      .WRITE_DATA_WIDTH_A(w),        // DECIMAL
      .WRITE_MODE_B("read_first")      // String
   )
   xpm_memory_sdpram_inst (
      .dbiterrb( ),             // 1-bit output: Status signal to indicate double bit error occurrence
                                       // on the data output of port B.

      .doutb(dout),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
      .sbiterrb( ),             // 1-bit output: Status signal to indicate single bit error occurrence
                                       // on the data output of port B.

      .addra(write_addr),                   // ADDR_WIDTH_A-bit input: Address for port A write operations.
      .addrb(read_addr),                   // ADDR_WIDTH_B-bit input: Address for port B read operations.
      .clka(clk),                     // 1-bit input: Clock signal for port A. Also clocks port B when
                                       // parameter CLOCKING_MODE is "common_clock".

      .clkb(clk),                     // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
                                       // "independent_clock". Unused when parameter CLOCKING_MODE is
                                       // "common_clock".

      .dina(din),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
      .ena(we),                       // 1-bit input: Memory enable signal for port A. Must be high on clock
                                       // cycles when write operations are initiated. Pipelined internally.

      .enb(re),                       // 1-bit input: Memory enable signal for port B. Must be high on clock
                                       // cycles when read operations are initiated. Pipelined internally.

      .injectdbiterra(1'b0), // 1-bit input: Controls double bit error injection on input data when
                                       // ECC enabled (Error injection capability is not available in
                                       // "decode_only" mode).

      .injectsbiterra(1'b0), // 1-bit input: Controls single bit error injection on input data when
                                       // ECC enabled (Error injection capability is not available in
                                       // "decode_only" mode).

      .regceb(1'b1),                 // 1-bit input: Clock Enable for the last register stage on the output
                                       // data path.

      .rstb(1'b0),                     // 1-bit input: Reset signal for the final port B output register stage.
                                       // Synchronously resets output port doutb to the value specified by
                                       // parameter READ_RESET_VALUE_B.

      .sleep(1'b0),                   // 1-bit input: sleep signal to enable the dynamic power saving feature.
      .wea(we)                        // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
                                       // for port A input data port dina. 1 bit wide when word-wide writes are
                                       // used. In byte-wide write configurations, each bit controls the
                                       // writing one byte of dina to address addra. For example, to
                                       // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
                                       // is 32, wea would be 4'b0010.
   );

endmodule
