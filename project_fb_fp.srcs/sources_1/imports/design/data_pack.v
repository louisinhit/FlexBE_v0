
module data_pack
# (
  parameter IN_WIDTH = 256,
  parameter OUT_WIDTH  = 1024
)  (
  //////////////////clock & control signals/////////////////
  input wire                   clk,
  input wire                   rst_n, 
  //////////////////Up data and signals/////////////
  input wire  [IN_WIDTH-1:0]              up_dat,
  input wire                                up_vld,
  output wire                               up_rdy,
  //////////////////Up data and signals/////////////
  output wire  [OUT_WIDTH-1:0]              dn_dat,
  output wire                               dn_vld,
  input  wire                               dn_rdy
);

localparam num_pack_cycle = OUT_WIDTH / IN_WIDTH;

genvar i;

assign up_rdy = 1;

reg  [IN_WIDTH-1:0]  up_dat_r[num_pack_cycle-1:0];

always @(posedge clk)
begin
  up_dat_r[0] <= up_dat;
end

assign dn_dat[IN_WIDTH-1:0] = up_dat_r[0];

generate
for(i=1 ; i<num_pack_cycle; i=i+1)
begin : ASSIGN_TIMING
    always @(posedge clk)
    begin
      up_dat_r[i] <= up_dat_r[i-1];
    end
    assign dn_dat[IN_WIDTH*i + IN_WIDTH - 1 : IN_WIDTH*i] = up_dat_r[i];
end
endgenerate


reg [16-1 : 0] in_counter;
reg dn_vld_reg;

always @(posedge clk)
if(!rst_n) begin
    in_counter <= 0;
    dn_vld_reg <= 0;
end else begin
    if (up_vld) begin
      if (in_counter == num_pack_cycle - 1) begin
        in_counter <= 0;
        dn_vld_reg <= 1;
      end else begin
        in_counter <= in_counter + 1;
        dn_vld_reg <= 0;
      end
    end
end

assign dn_vld = dn_vld_reg;
//////////////////Timing//////////////////

endmodule
