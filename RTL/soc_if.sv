`timescale 1ns/1ns
// Timescale definition:
// 1ns time unit, 1ns time precision
// Important for simulation delay resolution and timing accuracy


// =======================================================
// INTERFACE
// =======================================================

interface soc_if(input logic clk);

    // Active-low reset
    logic rst_n;

    // Write enable from CPU
    logic wr_en;

    // Read enable from CPU
    logic rd_en;

    // Address bus (memory-mapped)
    logic [7:0]  addr;

    // Write data bus
    logic [31:0] wdata;

    // Read data bus
    logic [31:0] rdata;

endinterface

