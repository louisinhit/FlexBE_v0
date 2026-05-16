
module ram_simple_dual
# (
  parameter w = 16,
  parameter d = 1024
)
(
  input                    clk,     // common clock for read/write access
  input                    rst_n,
  input                    we,
  input                    re,
  input   [$clog2(d)-1:0]  write_addr,
  input   [$clog2(d)-1:0]  read_addr,
  input   [w-1:0]          din,     // data in

  output  [w-1:0]          dout,
  output                   dout_vld
);

reg                 dout_vld_r;

always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    dout_vld_r <= 1'b0;
  end else begin
    dout_vld_r <= re;
  end
end

assign dout_vld = dout_vld_r;

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
ram_naive_1r1w  u_ram_naive_sdp (
  .clka(clk),    // input wire clka
  .ena(we),      // input wire ena // use as write port
  .wea(we),      // input wire [0 : 0] wea
  .addra(write_addr),  // input wire [6 : 0] addra
  .dina(din),    // input wire [127 : 0] dina
  .clkb(clk),    // input wire clkb
  .enb(re),      // input wire enb
  .addrb(read_addr),  // input wire [6 : 0] addrb
  .doutb(dout)  // output wire [127 : 0] doutb
);

endmodule
