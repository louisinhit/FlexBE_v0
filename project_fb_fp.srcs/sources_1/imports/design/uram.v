

module uram
# (
  parameter num_rams  = 16,
  parameter d         = 2048,
  parameter w         = 64,
  parameter addr_len  = 16

) (
  input                           clk,  // common clock for read/write access
  input                           rst_n,
  input                           we,   // active high write enable
  input  [num_rams*addr_len-1:0]  write_addr,   // write address
  input  [num_rams*w-1:0]         din,    // data in

  input                            re,   // active high read enable
  input   [num_rams*addr_len-1:0]  read_addr,   // read address
  output                           dout_vld,
  output  [num_rams*w-1:0]         dout     // data out
);

genvar i;

wire [addr_len-1:0]         write_addrs [num_rams-1:0];
wire [w-1:0]                dins        [num_rams-1:0];
wire [addr_len-1:0]         read_addrs  [num_rams-1:0];
wire [w-1:0]                douts       [num_rams-1:0];
wire                        douts_vld   [num_rams-1:0];

assign dout_vld = douts_vld[0];

generate
for(i=0 ; i<num_rams ; i=i+1)
begin : GENERATE_WIRING
    assign write_addrs[i] = write_addr[( addr_len*i + addr_len-1) : (addr_len*i)];
    assign dins[i] = din[( w*i + w-1) : (w*i)];
    assign read_addrs[i] = read_addr[( addr_len*i + addr_len-1) : (addr_len*i)];

    assign dout[( w*i + w-1) : (w*i)] = douts[i]; 
end

for(i=0 ; i<num_rams ; i=i+1)
begin : GENERATE_RAMS
    uram_top # (
      .w(w),
      .d(d)
    ) u_uram_simple_dual
    (
      .clk(clk),  // common clock for read/write access
      .rst_n(rst_n),
      .we(we),   // active high write enable
      .write_addr(write_addrs[i]),   // write address
      .din(dins[i]),    // data in
    
      .re(re),   // active high read enable
      .read_addr(read_addrs[i]),   // read address
      .dout_vld(douts_vld[i]),
      .dout(douts[i])     // data out
    ); // ram_simple_dual
end
endgenerate

endmodule
