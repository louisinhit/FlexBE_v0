`timescale 1ns / 1ps


module butterfly_indx_generator
# (
  // The data width of input data
  parameter data_width = 16,
  // The data width utilized for accumulated results
  parameter bu_parallelism = 8,
  parameter addr_len = 16
)
(
  input  wire                                clk,
  input  wire                                rst_n,
  input  wire                                start,
  input  wire [16-1:0]                       length,
  input  wire [16-1:0]                       num_seq,        // default is 1
  input  wire [8-1:0]                        sub_parallelsim,

  output wire                                butterfly_indx_finish,
  output wire                                butterfly_vld,
  output wire [addr_len*bu_parallelism-1:0]  butterfly_indx,
  output wire  [8-1:0]                       permute_state,
  output reg  [16-1:0]                       num_seq_r
);

localparam generating = 1'b1;
localparam idle = 1'b0;

/////////////////////Timing//////////////////////////
reg  [16-1:0]                          length_r;
// reg  [16-1:0]                          num_seq_r;
reg  [8-1:0]                           sub_r;

always @(posedge clk)
begin
    length_r <= length;
    sub_r <= sub_parallelsim;
end

//////////////// calculate the P_sub //////////////////////

reg  [8-1:0]                    log_sub;

function integer clogb2;
    input [16-1:0] value;
    integer n;
    begin
        clogb2 = 0;
        for(n = 0; 2**n < value; n = n + 1)
        clogb2 = n + 1;
    end
endfunction

always@(sub_r)
begin
    log_sub = clogb2(sub_r);
end

/////////////////////Timing//////////////////////////

genvar i;

reg                           state;
reg                           state_r;
reg  [16-1:0]                 stage;
reg  [16-1:0]                 stage_counter;
reg  [16-1:0]                 base;
reg  [16-1:0]                 mask;

// reg  [addr_len-1:0]           sequence [bu_parallelism-1:0];
wire  [addr_len-1:0]           sequence_r [bu_parallelism-1:0];
reg                           butterfly_indx_finish_r;

assign butterfly_vld = state_r;
assign butterfly_indx_finish = butterfly_indx_finish_r;

generate
for(i=0 ; i<bu_parallelism/2 ; i=i+1)
begin : GENERATE_BUTTERFLY_DAT
    assign butterfly_indx[( 2*addr_len*i + 2*addr_len-1) : (2*addr_len*i)] = {sequence_r[i*2+1], sequence_r[i*2]};
end
endgenerate


always @(posedge clk or negedge rst_n)
if(!rst_n) begin
    state <= idle;
    stage <= -1;
    stage_counter <= 0;
    mask <= 0;
    base <= 0;
    butterfly_indx_finish_r <= 1'b0;
    num_seq_r <= 0;
end
else if (state == generating) begin
    // after each stage

    if (num_seq_r == 1) begin
        if (base == (length_r/2 - bu_parallelism/2)) begin
            base <= 0;
            // check if is the last stage
            if ((stage - log_sub) == 0) begin
                state <= idle;
                stage <= -1;
                butterfly_indx_finish_r <= 1'b1;
                num_seq_r <= num_seq_r - 1;
            end else begin
                stage <= stage - 1;
                stage_counter <= stage_counter + 1;
                num_seq_r <= num_seq;
            end
        end else begin
            base <= base + bu_parallelism/2;
            num_seq_r <= num_seq;
        end
    end
    else begin
        num_seq_r <= num_seq_r - 1;
    end 
end
else if (state == idle) begin

    if (start) begin
        butterfly_indx_finish_r <= 1'b0;
        state <= generating;
        stage_counter <= 1;
        base <= 0;
        num_seq_r <= num_seq;
        // stage here corresponds to ii.
        if (length_r == 32768) begin
            stage <= 15-1;
            mask <= (16'b1 << 15) -1;
        end else if (length_r == 16384) begin
            stage <= 14-1;
            mask <= (16'b1 << 14) -1;
        end else if (length_r == 8192) begin
            stage <= 13-1;
            mask <= (16'b1 << 13) -1;
        end else if (length_r == 4096) begin
            stage <= 12-1;
            mask <= (16'b1 << 12) -1;
        end else if (length_r == 2048) begin
            stage <= 11-1;
            mask <= (16'b1 << 11) -1;
        end else if (length_r == 1024) begin
            stage <= 10-1;
            mask <= (16'b1 << 10) -1;
        end else if (length_r == 512) begin
            stage <= 9-1;
            mask <= (16'b1 << 9) -1;
        end else if (length_r == 256) begin
            stage <= 8-1;
            mask <= (16'b1 << 8) -1;
        end else if (length_r == 128) begin
            stage <= 7-1;
            mask <= (16'b1 << 7) -1;
        end else if (length_r == 64) begin
            stage <= 6-1;
            mask <= (16'b1 << 6) -1;
        end else if (length_r == 32) begin
            stage <= 5-1;
            mask <= (16'b1 << 5) -1;
        end else if (length_r == 16) begin
            stage <= 4-1;
            mask <= (16'b1 << 4) -1;
        end
    end else begin
        state <= idle;
        stage <= -1;
        mask <= 0;
        stage_counter <= 0;
        base <= 0;
        butterfly_indx_finish_r <= 1'b0;
        num_seq_r <= 0;
    end
end


// ======================   Calculation module  ==============================//

wire  [16-1:0]          base_tmp [bu_parallelism/2-1:0];
reg   [addr_len-1:0]    index [bu_parallelism/2-1:0];
wire  [addr_len-1:0]   ja [bu_parallelism/2-1:0];
wire  [addr_len-1:0]   jb [bu_parallelism/2-1:0];

reg  [16-1:0]                 stage_r;
reg  [16-1:0]                 stage_counter_r;

always @(posedge clk) begin
    stage_r <= stage;
    stage_counter_r <= stage_counter;
    state_r <= state;
end


generate
for(i=0 ; i<bu_parallelism/2 ; i=i+1) begin
    
    assign base_tmp[i] = base + i;
    // first stage
    always @(posedge clk) begin
        if (stage == 0) begin
            index[i] <= base_tmp[i];
        end else begin
            index[i] <= ((base_tmp[i] << stage_counter) & (mask >> 1)) | (base_tmp[i] >> (stage-1));
        end
    end

    assign ja[i] = index[i] << 1;
    assign jb[i] = (index[i] << 1) + 1;

    assign sequence_r[i*2]   = (stage_r == 0) ? ja[i] : (((ja[i] << stage_r) | (ja[i] >> stage_counter_r)) & mask);
    assign sequence_r[i*2+1] = (stage_r == 0) ? jb[i] : (((jb[i] << stage_r) | (jb[i] >> stage_counter_r)) & mask);

end
endgenerate

// ================= Permute and Rotate ======================== //

assign permute_state = (stage_r >= $clog2(bu_parallelism)) ?  0 : stage_r;

endmodule
