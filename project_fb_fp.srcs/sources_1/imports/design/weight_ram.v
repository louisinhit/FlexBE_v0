

module weight_ram
# (
  parameter BU_PARALLELISM = 4,
  parameter DATA_WIDTH     = 16,
  parameter DELAY_STAGE    = 1,
  parameter addr_len       = 16
) (
  //////////////////clock & control signals/////////////////
  input wire                     clk,
  input wire                     rst_n, 
  input wire  [16-1:0]           length,
  input wire  [8-1:0]            sub_parallelsim,
  input wire  [16-1:0]           num_seq,
  input wire                     butterfly_start,
  input wire                     butterfly_finish,
  input wire   [16-1:0]          model_counter,
  //////////////////Up data and signals/////////////
  input wire  [(4*DATA_WIDTH)*BU_PARALLELISM-1:0]  up_dat,
  input wire                                   up_vld,
  output wire                                  up_rdy,
  //////////////////Up data and signals/////////////
  output wire  [(4*DATA_WIDTH)*BU_PARALLELISM-1:0]  dn_dat, 
  output wire                                       dn_vld,
  input wire                                        dn_rdy
);

localparam num_rams = BU_PARALLELISM;   //32
genvar i;

assign up_rdy = 1;

///// Infer ROM for address map to layer /////  move to READ FROM FILE LATER
reg      [addr_len-1:0]  coeff_addr_indx [57:0];

  initial begin
      coeff_addr_indx[0]  = 16'd0;   // 0*5  
      coeff_addr_indx[1]  = 16'd5;   // 1*5  
      coeff_addr_indx[2]  = 16'd10;  // 2*5  
      coeff_addr_indx[3]  = 16'd15;  // 3*5  
      coeff_addr_indx[4]  = 16'd20;  // 4*5  
      coeff_addr_indx[5]  = 16'd25;  // 5*5  
      coeff_addr_indx[6]  = 16'd30;  // 6*5  
      coeff_addr_indx[7]  = 16'd35;  // 7*5  
      coeff_addr_indx[8]  = 16'd40;  // 8*5  
      coeff_addr_indx[9]  = 16'd45;  // 9*5  
      coeff_addr_indx[10] = 16'd50;  // 10*5  
      coeff_addr_indx[11] = 16'd55;  // 11*5  
      coeff_addr_indx[12] = 16'd60;  // 12*5  
      coeff_addr_indx[13] = 16'd65;  // 13*5  
      coeff_addr_indx[14] = 16'd70;  // 14*5  
      coeff_addr_indx[15] = 16'd75;  // 15*5  
      coeff_addr_indx[16] = 16'd80;  // 16*5  
      coeff_addr_indx[17] = 16'd85;  // 17*5  
      coeff_addr_indx[18] = 16'd90;  // 18*5  
      coeff_addr_indx[19] = 16'd95;  // 19*5  
      coeff_addr_indx[20] = 16'd100; // 20*5  
      coeff_addr_indx[21] = 16'd105; // 21*5  
      coeff_addr_indx[22] = 16'd110; // 22*5  
      coeff_addr_indx[23] = 16'd115; // 23*5  
      coeff_addr_indx[24] = 16'd120; // 24*5  
      coeff_addr_indx[25] = 16'd125; // 25*5  
      coeff_addr_indx[26] = 16'd130; // 26*5  
      coeff_addr_indx[27] = 16'd135; // 27*5  

      coeff_addr_indx[28] = 16'd140;

      coeff_addr_indx[29] = 16'd15500;  // 15500 +  0*5
      coeff_addr_indx[30] = 16'd15505;  // 15500 +  1*5
      coeff_addr_indx[31] = 16'd15510;  // 15500 +  2*5
      coeff_addr_indx[32] = 16'd15515;  // 15500 +  3*5
      coeff_addr_indx[33] = 16'd15520;  // 15500 +  4*5
      coeff_addr_indx[34] = 16'd15525;  // 15500 +  5*5
      coeff_addr_indx[35] = 16'd15530;  // 15500 +  6*5
      coeff_addr_indx[36] = 16'd15535;  // 15500 +  7*5
      coeff_addr_indx[37] = 16'd15540;  // 15500 +  8*5
      coeff_addr_indx[38] = 16'd15545;  // 15500 +  9*5
      coeff_addr_indx[39] = 16'd15550;  // 15500 + 10*5
      coeff_addr_indx[40] = 16'd15555;  // 15500 + 11*5
      coeff_addr_indx[41] = 16'd15560;  // 15500 + 12*5
      coeff_addr_indx[42] = 16'd15565;  // 15500 + 13*5
      coeff_addr_indx[43] = 16'd15570;  // 15500 + 14*5
      coeff_addr_indx[44] = 16'd15575;  // 15500 + 15*5
      coeff_addr_indx[45] = 16'd15580;  // 15500 + 16*5
      coeff_addr_indx[46] = 16'd15585;  // 15500 + 17*5
      coeff_addr_indx[47] = 16'd15590;  // 15500 + 18*5
      coeff_addr_indx[48] = 16'd15595;  // 15500 + 19*5
      coeff_addr_indx[49] = 16'd15600;  // 15500 + 20*5
      coeff_addr_indx[50] = 16'd15605;  // 15500 + 21*5
      coeff_addr_indx[51] = 16'd15610;  // 15500 + 22*5
      coeff_addr_indx[52] = 16'd15615;  // 15500 + 23*5
      coeff_addr_indx[53] = 16'd15620;  // 15500 + 24*5
      coeff_addr_indx[54] = 16'd15625;  // 15500 + 25*5
      coeff_addr_indx[55] = 16'd15630;  // 15500 + 26*5
      coeff_addr_indx[56] = 16'd15635;  // 15500 + 27*5

      coeff_addr_indx[57] = 16'd15640;  // preserve  NOT USED
  end


/////////////////////Timing//////////////////////////
reg  [16-1:0]                          length_r;
always @(posedge clk)
begin
    length_r <= length;
end

/////////////////////Timing//////////////////////////
reg  [addr_len-1:0]                        write_addr;

reg                                       read_vld;
wire  [addr_len-1:0]                      read_addr;
wire                                      ram_dn_vld;
wire  [(4*DATA_WIDTH)*BU_PARALLELISM-1:0] ram_dn_dat;

reg                                    butterfly_starts[DELAY_STAGE-1:0];

// LUT to get the total number of weight according to length
reg  [8-1:0]                           num_psub;

function integer clogb2;
    input [16-1:0] value;
    integer n;
    begin
        clogb2 = 0;
        for(n = 0; 2**n < value; n = n + 1)
        clogb2 = n + 1;
    end
endfunction

always@(sub_parallelsim)
begin
    num_psub = clogb2(sub_parallelsim);  // psub=8 numpsub=3
end

////////////////////////////////
always @(posedge clk or negedge rst_n)
if(!rst_n) begin
  butterfly_starts[0] <= 0;
end
else begin
  butterfly_starts[0] <= butterfly_start;
end

generate
for(i=1 ; i<DELAY_STAGE ; i=i+1)
begin : ASSIGN_START_DELAY
  always @(posedge clk or negedge rst_n)
  if(!rst_n) begin
    butterfly_starts[i] <= 0;
  end
  else begin
    butterfly_starts[i] <= butterfly_starts[i-1];
  end
end
endgenerate

// =========================================================================== //
// Generate write address and data
// =========================================================================== //

always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    write_addr <= 0;
  end else begin
    if (up_vld) begin
      write_addr <= write_addr + 1;
    end
  end
end

// =========================================================================== //
// Instantiate  Uram.
// =========================================================================== //

uram # (
 .num_rams(BU_PARALLELISM),
 .d(15645),   // fft coe + classifier weights
 .w(4*DATA_WIDTH),
 .addr_len(addr_len)
) u_uram
(
  .clk(clk),        // common clock for read/write access
  .rst_n(rst_n),
  .we(up_vld),   // active high write enable
  .write_addr({num_rams{write_addr}}),   // write address
  .din(up_dat),    // data in

  .re(read_vld),
  .read_addr({num_rams{read_addr}}),   // read address
  .dout_vld(ram_dn_vld),
  .dout(ram_dn_dat)     // data out
); // ram_simple_dual

// =========================================================================== //
// Generate read address and data
// =========================================================================== //

reg [32-1:0]                           read_counter;
reg                                    read_flag;   // disable the output to match the timing
reg [32-1:0]                           stage;
reg [16-1:0]                           read_addr_pointer;

assign read_addr = coeff_addr_indx[model_counter] + read_addr_pointer;

always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    read_counter <= 0;
    stage <= 0;
    read_flag <= 0;
  end
  else begin
    if (butterfly_starts[DELAY_STAGE - 1]) begin
      stage <= length_r >> (1 + num_psub);  // initial the stage
      read_flag <= 0;
    end
    else if (butterfly_finish) begin
      stage <= 0;
      read_counter <= 0;
      read_flag <= 0;
    end
    else if ((stage != 0) && ram_dn_vld) begin
      if (read_counter == (length_r*num_seq - 2*BU_PARALLELISM)) begin
        read_counter <= 0;
        stage <= stage >> 1;

        if (stage == 1) begin
          read_flag <= 1'b1;
        end
      end else begin
        read_counter <= read_counter + 2*BU_PARALLELISM;
      end
    end
    else begin
      read_counter <= read_counter;
      read_flag <= read_flag;
    end
  end
end

// 计时计数器，用来统计已过的时钟周期数
reg [15:0] cycle_cnt;

always @(posedge clk or negedge rst_n)
if(!rst_n) begin
  read_vld <= 1'b0;
  read_addr_pointer <= 0;
  cycle_cnt <= 0;
end
else begin
  
  if (butterfly_starts[DELAY_STAGE - 1]) begin
    // cycle_cnt <= {8'h00, num_seq[0]};
    cycle_cnt <= 0;
  end
  else if (stage != 0) begin
    read_vld <= 1'b1;

    if (cycle_cnt == (num_seq)) begin
      cycle_cnt <= 1;     // 重新归零
      read_addr_pointer <= read_addr_pointer + 1;  // 每满 num 个周期，指针加 1
    end else begin
      cycle_cnt <= cycle_cnt + 1;
    end
  end
  else begin
    read_vld <= 1'b0;
    read_addr_pointer <= 0;
    cycle_cnt <= 0;
  end
end


reg  [(4*DATA_WIDTH)*BU_PARALLELISM-1:0]  dn_dat_r; 
reg                                       dn_vld_r;

always @(posedge clk or negedge rst_n)
if(!rst_n) begin
    dn_vld_r <= 0;
end
else begin
    dn_vld_r <= read_flag ? 0 : ram_dn_vld;
end

always @(posedge clk)
begin
    dn_dat_r <= ram_dn_dat;
end

assign dn_vld = dn_vld_r;
assign dn_dat = dn_dat_r;

endmodule
