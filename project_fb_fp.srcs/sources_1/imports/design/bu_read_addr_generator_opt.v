
module bu_read_addr_generator_opt
# (
  // The data width of input data
  parameter data_width = 16,
  // The data width utilized for accumulated results
  parameter bu_parallelism = 16,
  parameter addr_len = 16
)
(
  input  wire                        clk,
  input  wire                        rst_n,
  // Control signal
  input  wire                        is_fft,
  input  wire                        is_bypass_p2s,
  input  wire                        keep_last_num,
  output  wire                        enable_p2s_A,
  output  wire                        enable_p2s_B,
  output  wire                        enable_p2s_fft,

  output  wire                        compute_A,
  output  wire                        compute_B,
  output  wire                        compute_FFT,

  input  wire                        butterfly_indx_finish, // Connect to butterfly indexing module
  output  wire                        butterfly_read_finish, // Propage to butterfly engine

  input wire                        butterfly_start_A, // Get from bu_engine
  input wire                        butterfly_start_B, // Get from bu_engine
  input wire                        butterfly_start_fft, // Get from bu_engine

  input  wire                       seq_out_start_A, // Get from bu_read_addr_generator
  input  wire                       seq_out_start_B, // Get from bu_read_addr_generator
  input  wire                       seq_out_start_fft, // Get from bu_read_addr_generator

  output  wire                        seq_out_finish_A, // Output from bu_read_addr_generator
  output  wire                        seq_out_finish_B, // Output from bu_read_addr_generator

  input  wire  [16-1:0]               length,
  input  wire  [16-1:0]               num_seq,
  input  wire  [16-1:0]               num_seq_r,
  output wire  [16-1:0]               permute_A,
  output wire  [16-1:0]               recover_A,

  output wire [16-1:0]                permute_B,
  output wire [16-1:0]                recover_B,
  // In and Outputs,
  input  wire                                 butterfly_vld, // Get from butterfly indexing module
  input wire  [addr_len*bu_parallelism-1:0]   butterfly_indx, // Get from butterfly indexing module
  input wire  [8-1:0]                         permute_state,

  output wire                        read_vld_A,
  output wire                        read_vld_B,
  output wire  [addr_len*bu_parallelism-1:0]      read_addr_A,    //  need to be fixed
  output wire  [addr_len*bu_parallelism-1:0]      read_addr_B
);

localparam seq_in_mode = 2'b00;
localparam seq_out_mode = 2'b01;
localparam idle = 2'b10;
localparam butterfly_mode = 2'b11;
localparam num_out_bits = $clog2(bu_parallelism);

/////////////////////Timing//////////////////////////

reg  [32-1:0]                          full_length_r;

always @(posedge clk)
begin
    if (keep_last_num == 1'b0) begin
        full_length_r <= length * num_seq;
    end else begin
        full_length_r <= length * num_seq * 8;
    end
end

reg                            is_fft_r;
always @(posedge clk)
begin
    is_fft_r <= is_fft;
end

reg                           is_bypass_p2s_r;
always @(posedge clk)
begin
    is_bypass_p2s_r <= is_bypass_p2s;
end

// =========================================================================== //
// Control state
// =========================================================================== //
reg                            compute_A_r;
reg                            compute_B_r;
reg                            compute_FFT_r;
// =========================for fft control state========================== //
reg [2-1:0]                    fft_state;
reg [16-1:0]                   out_counter_fft;
reg                            butterfly_read_finish_r_fft;

always @(posedge clk or negedge rst_n)
if(!rst_n) begin
    fft_state <= seq_in_mode;
    out_counter_fft <= 0;
    butterfly_read_finish_r_fft <= 1'b0;
    compute_FFT_r <= 1'b0;
end
else begin
    if (is_fft_r) begin
        if (fft_state == seq_in_mode) begin // positive
            out_counter_fft <= 0;
            compute_FFT_r <= 1'b0;
            butterfly_read_finish_r_fft <= 1'b0;
            if (butterfly_start_fft) begin
                compute_FFT_r <= 1'b1;
                fft_state <= butterfly_mode;
            end
        end
        else if (fft_state == butterfly_mode) begin
            out_counter_fft <= 0;
            compute_FFT_r <= 1'b1;
            butterfly_read_finish_r_fft <= 1'b0;
            if (butterfly_indx_finish) begin
                fft_state <= idle;
                compute_FFT_r <= 1'b0;
                butterfly_read_finish_r_fft <= 1'b1;
            end
        end
        else if (fft_state == idle) begin
            out_counter_fft <= 0;
            butterfly_read_finish_r_fft <= 1'b0;
            compute_FFT_r <= 1'b0;
            if (seq_out_start_fft) fft_state <= seq_out_mode;
        end
        else if (fft_state == seq_out_mode) begin
            butterfly_read_finish_r_fft <= 1'b0;
            compute_FFT_r <= 1'b0;
            if (is_bypass_p2s_r) begin // outputs bu_parallelism by bu_parallelism
                if (out_counter_fft == full_length_r - bu_parallelism) begin
                    fft_state <= seq_in_mode;
                    butterfly_read_finish_r_fft <= 1'b0;
                end
                else out_counter_fft <= out_counter_fft + bu_parallelism;
            end
            else begin // outputs one by one
                if (out_counter_fft == full_length_r - 1) begin
                    fft_state <= seq_in_mode;
                    butterfly_read_finish_r_fft <= 1'b0;
                end
                else out_counter_fft <= out_counter_fft + 1;
            end
        end
    end
    else begin
        fft_state <= seq_in_mode;
        out_counter_fft <= 0;
        butterfly_read_finish_r_fft <= 1'b0;
    end
end

assign compute_FFT = compute_FFT_r;


// =========================for butterfly control state========================== //

reg [2-1:0]                    bfly_state_A;
reg [16-1:0]                   out_counter_A;
reg                            butterfly_read_finish_r_A;
reg                            seq_out_finish_r_A;

always @(posedge clk or negedge rst_n)
if(!rst_n) begin
    bfly_state_A <= seq_in_mode;
    out_counter_A <= 0;
    butterfly_read_finish_r_A <= 1'b0;
    seq_out_finish_r_A <=1'b0;
    compute_A_r <= 1'b0;
end
else begin
    if (!is_fft_r) begin
        if (bfly_state_A == seq_in_mode) begin // positive
            out_counter_A <= 0;
            butterfly_read_finish_r_A <= 1'b0;
            seq_out_finish_r_A <=1'b0;
            compute_A_r <= 1'b0;
            if (butterfly_start_A) begin
                bfly_state_A <= butterfly_mode;
                compute_A_r <= 1'b1;
            end
        end
        else if (bfly_state_A == butterfly_mode) begin
            out_counter_A <= 0;
            butterfly_read_finish_r_A <= 1'b0;
            seq_out_finish_r_A <=1'b0;
            compute_A_r <= 1'b1;
            if (butterfly_indx_finish) begin
                bfly_state_A <= idle;
                butterfly_read_finish_r_A <= 1'b1;
                seq_out_finish_r_A <= 1'b0;
                compute_A_r <= 1'b0;
            end
        end
        else if (bfly_state_A == idle) begin
            out_counter_A <= 0;
            butterfly_read_finish_r_A <= 1'b0;
            seq_out_finish_r_A <=1'b0;
            compute_A_r <= 1'b0;
            if (seq_out_start_A) bfly_state_A <= seq_out_mode;
        end
        else if (bfly_state_A == seq_out_mode) begin
            butterfly_read_finish_r_A <= 1'b0;
            seq_out_finish_r_A <=1'b0;
            compute_A_r <= 1'b0;
            if (is_bypass_p2s_r) begin // outputs bu_parallelism by bu_parallelism
                if (out_counter_A == full_length_r - bu_parallelism) begin
                    bfly_state_A <= seq_in_mode;
                    butterfly_read_finish_r_A <= 1'b0;
                    seq_out_finish_r_A <=1'b1;
                end
                else out_counter_A <= out_counter_A + bu_parallelism;
            end
            else begin // outputs one by one
                if (out_counter_A == full_length_r - 1) begin
                    bfly_state_A <= seq_in_mode;
                    butterfly_read_finish_r_A <= 1'b0;
                    seq_out_finish_r_A <=1'b1;
                end
                else out_counter_A <= out_counter_A + 1;
            end
        end
    end
    else begin
        bfly_state_A <= seq_in_mode;
        out_counter_A <= 0;
        butterfly_read_finish_r_A <= 1'b0;
        seq_out_finish_r_A <=1'b0;
    end
end
assign seq_out_finish_A = seq_out_finish_r_A;
assign compute_A = compute_A_r;

reg [2-1:0]                    bfly_state_B;
reg [16-1:0]                   out_counter_B;
reg                            butterfly_read_finish_r_B;
reg                            seq_out_finish_r_B;

always @(posedge clk or negedge rst_n)
if(!rst_n) begin
    bfly_state_B <= seq_in_mode;
    out_counter_B <= 0;
    butterfly_read_finish_r_B <= 1'b0;
    seq_out_finish_r_B <=1'b0;
    compute_B_r <= 1'b0;
end
else begin
    if (!is_fft_r) begin
        if (bfly_state_B == seq_in_mode) begin // positive
            out_counter_B <= 0;
            butterfly_read_finish_r_B <= 1'b0;
            seq_out_finish_r_B <=1'b0;
            compute_B_r <= 1'b0;
            if (butterfly_start_B) begin
                bfly_state_B <= butterfly_mode;
                compute_B_r <= 1'b1;
            end
        end
        else if (bfly_state_B == butterfly_mode) begin
            out_counter_B <= 0;
            butterfly_read_finish_r_B <= 1'b0;
            seq_out_finish_r_B <=1'b0;
            compute_B_r <= 1'b1;
            if (butterfly_indx_finish) begin
                bfly_state_B <= idle;
                butterfly_read_finish_r_B <= 1'b1;
                seq_out_finish_r_B <= 1'b0;
                compute_B_r <= 1'b0;
            end
        end
        else if (bfly_state_B == idle) begin
            out_counter_B <= 0;
            butterfly_read_finish_r_B <= 1'b0;
            seq_out_finish_r_B <=1'b0;
            compute_B_r <= 1'b0;
            if (seq_out_start_B) bfly_state_B <= seq_out_mode;
        end
        else if (bfly_state_B == seq_out_mode) begin
            butterfly_read_finish_r_B <= 1'b0;
            seq_out_finish_r_B <=1'b0;
            compute_B_r <= 1'b0;
            if (is_bypass_p2s_r) begin // outputs bu_parallelism by bu_parallelism
                if (out_counter_B == full_length_r - bu_parallelism) begin
                    bfly_state_B <= seq_in_mode;
                    butterfly_read_finish_r_B <= 1'b0;
                    seq_out_finish_r_B <=1'b1;
                end
                else out_counter_B <= out_counter_B + bu_parallelism;
            end
            else begin // outputs one by one
                if (out_counter_B == full_length_r - 1) begin
                    bfly_state_B <= seq_in_mode;
                    butterfly_read_finish_r_B <= 1'b0;
                    seq_out_finish_r_B <=1'b1;
                end
                else out_counter_B <= out_counter_B + 1;
            end
        end
    end
    else begin
        bfly_state_B <= seq_in_mode;
        out_counter_B <= 0;
        butterfly_read_finish_r_B <= 1'b0;
        seq_out_finish_r_B <=1'b0;
    end
end
assign seq_out_finish_B = seq_out_finish_r_B;
assign compute_B = compute_B_r;


// =========================================================================== //
// Generate read address for different modes
// =========================================================================== //

wire [16-1:0]  out_counter;
wire [2-1:0]   bfly_state;

assign out_counter = is_fft_r ?  out_counter_fft : out_counter_A;
assign bfly_state  = is_fft_r ?  fft_state : bfly_state_A;


/////////////////////Timing//////////////////////////

wire [addr_len*bu_parallelism-1:0]        read_addrs;
wire [16-1:0]                             permute;
wire [16-1:0]                             recover;

reg                            bfly_read_vld_r_A;
reg                            bfly_read_vld_r_B;
reg                            fft_read_vld_r;

reg                            bfly_enable_p2s_r_A;
reg                            bfly_enable_p2s_r_B;
reg                            fft_enable_p2s_r;

 addr_generator # (
   .bu_parallelism(bu_parallelism),
   .addr_len(addr_len)
  )  u_addr_generator_A (
    .clk(clk),
    .rst_n(rst_n),
    .butterfly_indx(butterfly_indx),
    .out_counter(out_counter),
    .bfly_state(bfly_state),
    .permute_state(permute_state),
    .num_seq(num_seq),
    .num_seq_r(num_seq_r),

    .read_addrs(read_addr_A),   // todo need to fix
    .permute_rotate(permute_A),
    .recover_rotate(recover_A)
    );

//  addr_generator # (
//    .bu_parallelism(bu_parallelism),
//    .addr_len(addr_len)
//   )  u_addr_generator_B (
//     .clk(clk),
//     .rst_n(rst_n),
//     .butterfly_indx(butterfly_indx),
//     .out_counter(out_counter_B),
//     .bfly_state(bfly_state_B),
//     .permute_state(permute_state),

//     .read_addrs(read_addrs),
//     .permute_rotate(permute),
//     .recover_rotate(recover)
//     );


// // Generate final read address
// assign read_addr_B = is_fft_r?  read_addr_A : read_addrs;
// assign permute_B = is_fft_r? permute_A : permute;
// assign recover_B = is_fft_r? recover_A : recover;

// // Generate final read address disconnect the B controller, just copy from A
assign read_addr_B = read_addr_A;
assign permute_B = permute_A;
assign recover_B = recover_A;


// =========================================================================== //
// Generate read address for Dn_vld
// =========================================================================== //

// ====================dn_vld for butterfly============================== //
always @(posedge clk or negedge rst_n)
if(!rst_n) begin
    bfly_read_vld_r_A <= 1'b0;
    bfly_enable_p2s_r_A <= 1'b0;
end
else begin
    if (bfly_state_A == seq_in_mode) begin // positive
        bfly_read_vld_r_A <= 1'b0;
        bfly_enable_p2s_r_A <= 1'b0;
    end
    else if (bfly_state_A == butterfly_mode) begin
        bfly_read_vld_r_A <= butterfly_vld; 
        bfly_enable_p2s_r_A <= 1'b0;
    end
    else if (bfly_state_A == idle) begin 
        bfly_read_vld_r_A <= 1'b0; 
        bfly_enable_p2s_r_A <= 1'b0;
    end
    else if (bfly_state_A == seq_out_mode) begin
        bfly_enable_p2s_r_A <= 1'b1;
        if (is_bypass_p2s_r) begin 
            bfly_read_vld_r_A <= 1'b1;
        end else begin
            if (out_counter_A[num_out_bits-1:0] == {num_out_bits{1'b0}}) bfly_read_vld_r_A <= 1'b1;
            else bfly_read_vld_r_A <= 1'b0;
        end
    end
end

always @(posedge clk or negedge rst_n)
if(!rst_n) begin
    bfly_read_vld_r_B <= 1'b0;
    bfly_enable_p2s_r_B <= 1'b0;
end
else begin
    if (bfly_state_B == seq_in_mode) begin // positive
        bfly_read_vld_r_B <= 1'b0;
        bfly_enable_p2s_r_B <= 1'b0;
    end
    else if (bfly_state_B == butterfly_mode) begin
        bfly_read_vld_r_B <= butterfly_vld; 
        bfly_enable_p2s_r_B <= 1'b0;
    end
    else if (bfly_state_B == idle) begin 
        bfly_read_vld_r_B <= 1'b0; 
        bfly_enable_p2s_r_B <= 1'b0;
    end
    else if (bfly_state_B == seq_out_mode) begin
        bfly_enable_p2s_r_B <= 1'b1;
        if (is_bypass_p2s_r) begin 
            bfly_read_vld_r_B <= 1'b1;
        end else begin
            if (out_counter_B[num_out_bits-1:0] == {num_out_bits{1'b0}}) bfly_read_vld_r_B <= 1'b1;
            else bfly_read_vld_r_B <= 1'b0;
        end
    end
end

// ====================dn_vld for FFT============================== //
always @(posedge clk or negedge rst_n)
if(!rst_n) begin
    fft_read_vld_r <= 1'b0;
    fft_enable_p2s_r <= 1'b0;
end
else begin
    if (fft_state == seq_in_mode) begin // positive
        fft_read_vld_r <= 1'b0;
        fft_enable_p2s_r <= 1'b0;
    end
    else if (fft_state == butterfly_mode) begin
        fft_read_vld_r <= butterfly_vld; 
        fft_enable_p2s_r <= 1'b0;
    end
    else if (fft_state == idle) begin 
        fft_read_vld_r <= 1'b0; 
        fft_enable_p2s_r <= 1'b0;
    end
    else if (fft_state == seq_out_mode) begin
        fft_enable_p2s_r <= 1'b1;
        if (is_bypass_p2s_r) begin 
            fft_read_vld_r <= 1'b1;
        end else begin
            if (out_counter_fft[num_out_bits-1:0] == {num_out_bits{1'b0}}) fft_read_vld_r <= 1'b1;
            else fft_read_vld_r <= 1'b0;
        end
    end
end


// ====================dn_vld for final============================== //

assign enable_p2s_fft = fft_enable_p2s_r;
assign enable_p2s_A = bfly_enable_p2s_r_A;
assign enable_p2s_B = bfly_enable_p2s_r_B;

assign read_vld_A = is_fft_r ? fft_read_vld_r : bfly_read_vld_r_A;
assign read_vld_B = is_fft_r ? fft_read_vld_r : bfly_read_vld_r_B;
assign butterfly_read_finish = butterfly_read_finish_r_fft | butterfly_read_finish_r_B | butterfly_read_finish_r_A;

endmodule
