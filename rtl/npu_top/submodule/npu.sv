////////////////////////////////////////////////////////////////////////////////
// AS501
// Lab 7
// Activation Module
////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2024 by Smart Energy-Efficient Design Lab. (SEED), KAIST
// All rights reserved.
//
//                            Written by Hyungjoon Bae (jo_on@kaist.ac.kr)
//                            Supervised by Wanyeong Jung (wanyeong@kaist.ac.kr)
////////////////////////////////////////////////////////////////////////////////

module NPU #(
    parameter DWidth = 32
)(
    // Basic signals
    input   logic                   clk_i,
    input   logic                   rst_ni,
    // From interface
    input   logic                   wen_type_i,
    input   logic                   wen_input_i,
    input   logic   [DWidth-1:0]    addr_i,
    input   logic   [DWidth-1:0]    wdata_i,
    // To master
    output  logic   [DWidth-1:0]    rdata_o
);
    localparam AddrWidth = 32;
    localparam TypeAddr   = 'h0;
    localparam InputAddr  = 'h4;
    localparam OutputAddr = 'h8;

    ram #(
        .DATA_WIDTH(DWidth),
        .ADDR_WIDTH(AddrWidth),
        .OUTPUT_REG(0) // not use we keep read_addr 
    ) sram (
        .clk(clk),
        .reset(rst_ni),
        .read_req(1'b0),   //since we not use REG
        .read_addr(addr_i),
        .read_data(rdata_o),   //output
        .write_req(wen_input_i),
        .write_addr(addr_i),
        .write_data(wdata_i)
    );

////////////////////////////////////////////////////////////////////////////////

endmodule