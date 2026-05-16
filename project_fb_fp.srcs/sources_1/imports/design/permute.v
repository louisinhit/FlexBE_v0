    // `timescale 1ns / 1ps

    // module read_permute # (
    //   parameter ports      = 8,
    //   parameter data_width = 16
    // )
    // (
    //   input  wire  [ports * data_width-1:0]  up_dat,
    //   input  wire  [8-1:0]                   sel,
    //   output reg   [ports * data_width-1:0]  dn_dat
    // );

    // always @(*) begin
    //     case (sel)
    //         8'd2	: dn_dat = {up_dat[data_width*8-1:data_width*7],
    //                             up_dat[data_width*4-1:data_width*3],
    //                             up_dat[data_width*6-1:data_width*5],
    //                             up_dat[data_width*2-1:data_width*1],
    //                             up_dat[data_width*7-1:data_width*6],
    //                             up_dat[data_width*3-1:data_width*2],
    //                             up_dat[data_width*5-1:data_width*4],
    //                         up_dat[data_width-1:0]}; 
    //             8'd1	: dn_dat = {up_dat[data_width*8-1:data_width*7],
    //                             up_dat[data_width*6-1:data_width*5],
    //                             up_dat[data_width*4-1:data_width*3],
    //                             up_dat[data_width*2-1:data_width*1],
    //                             up_dat[data_width*7-1:data_width*6],
    //                             up_dat[data_width*5-1:data_width*4],
    //                             up_dat[data_width*3-1:data_width*2],
    //                         up_dat[data_width-1:0]}; 
    //             default : dn_dat = up_dat;
    //     endcase
    // end

    // endmodule

    // module write_permute # (
    //   parameter ports      = 8,
    //   parameter data_width = 16
    // )
    // (
    //   input  wire  [ports * data_width-1:0]  up_dat,
    //   input  wire  [8-1:0]                   sel,
    //   output reg   [ports * data_width-1:0]  dn_dat
    // );

    // always @(*) begin
    //     case (sel)
    //         8'd2	: dn_dat = {up_dat[data_width*8-1:data_width*7],
    //                             up_dat[data_width*4-1:data_width*3],
    //                             up_dat[data_width*6-1:data_width*5],
    //                             up_dat[data_width*2-1:data_width*1],
    //                             up_dat[data_width*7-1:data_width*6],
    //                             up_dat[data_width*3-1:data_width*2],
    //                             up_dat[data_width*5-1:data_width*4],
    //                         up_dat[data_width-1:0]}; 
    //             8'd1	: dn_dat = {up_dat[data_width*8-1:data_width*7],
    //                             up_dat[data_width*4-1:data_width*3],
    //                             up_dat[data_width*7-1:data_width*6],
    //                             up_dat[data_width*3-1:data_width*2],
    //                             up_dat[data_width*6-1:data_width*5],
    //                             up_dat[data_width*2-1:data_width*1],
    //                             up_dat[data_width*5-1:data_width*4],
    //                         up_dat[data_width-1:0]}; 
    //             default : dn_dat = up_dat;
    //     endcase
    // end

    // endmodule




    module read_permute # (
      parameter ports      = 16,
      parameter data_width = 16
    )
    (
      input  wire  [ports * data_width-1:0]  up_dat,
      input  wire  [8-1:0]                   sel,
      output reg   [ports * data_width-1:0]  dn_dat
    );

    always @(*) begin
        case (sel)
            8'd3	: dn_dat = {up_dat[data_width*16-1:data_width*15],
                                up_dat[data_width*8-1:data_width*7],
                                up_dat[data_width*14-1:data_width*13],
                                up_dat[data_width*6-1:data_width*5],
                                up_dat[data_width*12-1:data_width*11],
                                up_dat[data_width*4-1:data_width*3],
                                up_dat[data_width*10-1:data_width*9],
                                up_dat[data_width*2-1:data_width*1],
                                up_dat[data_width*15-1:data_width*14],
                                up_dat[data_width*7-1:data_width*6],
                                up_dat[data_width*13-1:data_width*12],
                                up_dat[data_width*5-1:data_width*4],
                                up_dat[data_width*11-1:data_width*10],
                                up_dat[data_width*3-1:data_width*2],
                                up_dat[data_width*9-1:data_width*8],
                            up_dat[data_width-1:0]}; 
                8'd2	: dn_dat = {up_dat[data_width*16-1:data_width*15],
                                up_dat[data_width*12-1:data_width*11],
                                up_dat[data_width*14-1:data_width*13],
                                up_dat[data_width*10-1:data_width*9],
                                up_dat[data_width*8-1:data_width*7],
                                up_dat[data_width*4-1:data_width*3],
                                up_dat[data_width*6-1:data_width*5],
                                up_dat[data_width*2-1:data_width*1],
                                up_dat[data_width*15-1:data_width*14],
                                up_dat[data_width*11-1:data_width*10],
                                up_dat[data_width*13-1:data_width*12],
                                up_dat[data_width*9-1:data_width*8],
                                up_dat[data_width*7-1:data_width*6],
                                up_dat[data_width*3-1:data_width*2],
                                up_dat[data_width*5-1:data_width*4],
                            up_dat[data_width-1:0]}; 
                8'd1	: dn_dat = {up_dat[data_width*16-1:data_width*15],
                                up_dat[data_width*14-1:data_width*13],
                                up_dat[data_width*12-1:data_width*11],
                                up_dat[data_width*10-1:data_width*9],
                                up_dat[data_width*8-1:data_width*7],
                                up_dat[data_width*6-1:data_width*5],
                                up_dat[data_width*4-1:data_width*3],
                                up_dat[data_width*2-1:data_width*1],
                                up_dat[data_width*15-1:data_width*14],
                                up_dat[data_width*13-1:data_width*12],
                                up_dat[data_width*11-1:data_width*10],
                                up_dat[data_width*9-1:data_width*8],
                                up_dat[data_width*7-1:data_width*6],
                                up_dat[data_width*5-1:data_width*4],
                                up_dat[data_width*3-1:data_width*2],
                            up_dat[data_width-1:0]}; 
                default : dn_dat = up_dat;
        endcase
    end

    endmodule

    module write_permute # (
      parameter ports      = 16,
      parameter data_width = 16
    )
    (
      input  wire  [ports * data_width-1:0]  up_dat,
      input  wire  [8-1:0]                   sel,
      output reg   [ports * data_width-1:0]  dn_dat
    );

    always @(*) begin
        case (sel)
            8'd3	: dn_dat = {up_dat[data_width*16-1:data_width*15],
                                up_dat[data_width*8-1:data_width*7],
                                up_dat[data_width*14-1:data_width*13],
                                up_dat[data_width*6-1:data_width*5],
                                up_dat[data_width*12-1:data_width*11],
                                up_dat[data_width*4-1:data_width*3],
                                up_dat[data_width*10-1:data_width*9],
                                up_dat[data_width*2-1:data_width*1],
                                up_dat[data_width*15-1:data_width*14],
                                up_dat[data_width*7-1:data_width*6],
                                up_dat[data_width*13-1:data_width*12],
                                up_dat[data_width*5-1:data_width*4],
                                up_dat[data_width*11-1:data_width*10],
                                up_dat[data_width*3-1:data_width*2],
                                up_dat[data_width*9-1:data_width*8],
                            up_dat[data_width-1:0]}; 
                8'd2	: dn_dat = {up_dat[data_width*16-1:data_width*15],
                                up_dat[data_width*8-1:data_width*7],
                                up_dat[data_width*14-1:data_width*13],
                                up_dat[data_width*6-1:data_width*5],
                                up_dat[data_width*15-1:data_width*14],
                                up_dat[data_width*7-1:data_width*6],
                                up_dat[data_width*13-1:data_width*12],
                                up_dat[data_width*5-1:data_width*4],
                                up_dat[data_width*12-1:data_width*11],
                                up_dat[data_width*4-1:data_width*3],
                                up_dat[data_width*10-1:data_width*9],
                                up_dat[data_width*2-1:data_width*1],
                                up_dat[data_width*11-1:data_width*10],
                                up_dat[data_width*3-1:data_width*2],
                                up_dat[data_width*9-1:data_width*8],
                            up_dat[data_width-1:0]}; 
                8'd1	: dn_dat = {up_dat[data_width*16-1:data_width*15],
                                up_dat[data_width*8-1:data_width*7],
                                up_dat[data_width*15-1:data_width*14],
                                up_dat[data_width*7-1:data_width*6],
                                up_dat[data_width*14-1:data_width*13],
                                up_dat[data_width*6-1:data_width*5],
                                up_dat[data_width*13-1:data_width*12],
                                up_dat[data_width*5-1:data_width*4],
                                up_dat[data_width*12-1:data_width*11],
                                up_dat[data_width*4-1:data_width*3],
                                up_dat[data_width*11-1:data_width*10],
                                up_dat[data_width*3-1:data_width*2],
                                up_dat[data_width*10-1:data_width*9],
                                up_dat[data_width*2-1:data_width*1],
                                up_dat[data_width*9-1:data_width*8],
                            up_dat[data_width-1:0]}; 
                default : dn_dat = up_dat;
        endcase
    end

    endmodule
