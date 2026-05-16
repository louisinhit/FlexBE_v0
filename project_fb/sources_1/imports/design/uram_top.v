`timescale  1ns / 1ps

module uram_top
#(
   parameter w = 64,
   parameter d = 1024,
   parameter ADDR_WIDTH = $clog2(d)
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

localparam DATA_WIDTH = 72;

wire [DATA_WIDTH-1:0]   doutb;
reg                     dout_vld_r;

always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    dout_vld_r <= 1'b0;
  end else begin
    dout_vld_r <= re;
  end
end

assign dout_vld = dout_vld_r;
assign dout = doutb[w-1:0];

   xpm_memory_sdpram #(
      .ADDR_WIDTH_A(ADDR_WIDTH),               // DECIMAL
      .ADDR_WIDTH_B(ADDR_WIDTH),               // DECIMAL
      .AUTO_SLEEP_TIME(0),            // DECIMAL
      .BYTE_WRITE_WIDTH_A(DATA_WIDTH),        // DECIMAL
      .CASCADE_HEIGHT(0),             // DECIMAL
      .CLOCKING_MODE("common_clock"), // String
      .ECC_MODE("no_ecc"),            // String
      .MEMORY_INIT_FILE("none"),      // String
      .MEMORY_INIT_PARAM("0"),        // String
      .MEMORY_OPTIMIZATION("true"),   // String
      .MEMORY_PRIMITIVE("ultra"),      // String
      .MEMORY_SIZE(DATA_WIDTH*d),             // DECIMAL    72 * 1024 Maximum depth 4096
      .MESSAGE_CONTROL(0),            // DECIMAL
      .READ_DATA_WIDTH_B(DATA_WIDTH),         // DECIMAL
      .READ_LATENCY_B(1),             // DECIMAL
      .READ_RESET_VALUE_B("0"),       // String
      .RST_MODE_A("SYNC"),            // String
      .RST_MODE_B("SYNC"),            // String
      .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
      .USE_MEM_INIT(0),               // DECIMAL
      .WAKEUP_TIME("disable_sleep"),  // String
      .WRITE_DATA_WIDTH_A(DATA_WIDTH),        // DECIMAL
      .WRITE_MODE_B("read_first")      // String
   )
   xpm_memory_sdpram_inst (
      .dbiterrb( ),             // 1-bit output: Status signal to indicate double bit error occurrence
                                       // on the data output of port B.

      .doutb(doutb),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
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
