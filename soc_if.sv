// ============================================================
// SoC Interface (for CPU master)
// ============================================================

interface soc_if(input logic clk);

    logic rst_n;

    logic wr_en;
    logic rd_en;
    logic [7:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    clocking cb @(posedge clk);
        output wr_en, rd_en, addr, wdata;
        input  rdata;
    endclocking

endinterface
