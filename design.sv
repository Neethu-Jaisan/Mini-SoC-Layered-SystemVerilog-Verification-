// ============================================================
// design.sv
// Mini SoC DUT (Arbiter + FIFO + Timer + GPIO)
// ============================================================

`timescale 1ns/1ns

// ============================================================
// INTERFACE
// ============================================================

interface soc_if(input logic clk);

    logic rst_n;

    logic        wr_en;
    logic        rd_en;
    logic [7:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    // Clocking block for race-free driving
    clocking cb @(posedge clk);
        output wr_en, rd_en, addr, wdata;
        input  rdata;
    endclocking

endinterface


// ============================================================
// FIXED PRIORITY ARBITER (CPU > DMA)
// ============================================================

module bus_arbiter(
    input  logic req_cpu,
    input  logic req_dma,
    output logic grant_cpu,
    output logic grant_dma
);

    always_comb begin
        grant_cpu = 0;
        grant_dma = 0;

        if(req_cpu)
            grant_cpu = 1;
        else if(req_dma)
            grant_dma = 1;
    end

endmodule


// ============================================================
// SIMPLE SYNCHRONOUS FIFO
// ============================================================

module fifo #(
    parameter WIDTH = 32,
    parameter DEPTH = 8
)(
    input  logic clk,
    input  logic rst_n,
    input  logic wr_en,
    input  logic rd_en,
    input  logic [WIDTH-1:0] wdata,
    output logic [WIDTH-1:0] rdata,
    output logic full,
    output logic empty
);

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [$clog2(DEPTH):0] wr_ptr, rd_ptr;
    logic [$clog2(DEPTH+1):0] count;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            wr_ptr <= 0;
        else if(wr_en && !full) begin
            mem[wr_ptr] <= wdata;
            wr_ptr <= wr_ptr + 1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rd_ptr <= 0;
            rdata  <= 0;
        end
        else if(rd_en && !empty) begin
            rdata <= mem[rd_ptr];
            rd_ptr <= rd_ptr + 1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            count <= 0;
        else begin
            case({wr_en && !full, rd_en && !empty})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: count <= count;
            endcase
        end
    end

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

endmodule


// ============================================================
// MINI SOC TOP
// ============================================================

module mini_soc(
    input  logic clk,
    input  logic rst_n,

    // CPU master
    input  logic        cpu_wr_en,
    input  logic        cpu_rd_en,
    input  logic [7:0]  cpu_addr,
    input  logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata,

    // DMA master (unused in TB, but present architecturally)
    input  logic        dma_wr_en,
    input  logic        dma_rd_en,
    input  logic [7:0]  dma_addr,
    input  logic [31:0] dma_wdata,
    output logic [31:0] dma_rdata,

    output logic irq
);

    logic wr_en, rd_en;
    logic [7:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    logic grant_cpu, grant_dma;

    // Arbiter instance
    bus_arbiter arb(
        .req_cpu(cpu_wr_en | cpu_rd_en),
        .req_dma(dma_wr_en | dma_rd_en),
        .grant_cpu(grant_cpu),
        .grant_dma(grant_dma)
    );

    // Bus selection
    always_comb begin
        wr_en = 0;
        rd_en = 0;
        addr  = 0;
        wdata = 0;
        cpu_rdata = 0;
        dma_rdata = 0;

        if(grant_cpu) begin
            wr_en = cpu_wr_en;
            rd_en = cpu_rd_en;
            addr  = cpu_addr;
            wdata = cpu_wdata;
            cpu_rdata = rdata;
        end
        else if(grant_dma) begin
            wr_en = dma_wr_en;
            rd_en = dma_rd_en;
            addr  = dma_addr;
            wdata = dma_wdata;
            dma_rdata = rdata;
        end
    end

    // Registers
    logic [31:0] control_reg;
    logic [3:0]  gpio_reg;
    logic [31:0] timer_reg;

    // Timer
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            timer_reg <= 0;
        else if(control_reg[0])
            timer_reg <= timer_reg + 1;
    end

    // FIFO
    logic fifo_full, fifo_empty;
    logic [31:0] fifo_rdata;

    fifo fifo_inst(
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en && addr == 8'h10),
        .rd_en(rd_en && addr == 8'h14),
        .wdata(wdata),
        .rdata(fifo_rdata),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    // Register write
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            control_reg <= 0;
            gpio_reg    <= 0;
        end
        else if(wr_en) begin
            case(addr)
                8'h00: control_reg <= wdata;
                8'h04: gpio_reg    <= wdata[3:0];
            endcase
        end
    end

    // Read logic
    always_comb begin
        rdata = 0;

        if(rd_en) begin
            case(addr)
                8'h00: rdata = control_reg;
                8'h04: rdata = {28'b0, gpio_reg};
                8'h08: rdata = timer_reg;
                8'h14: rdata = fifo_rdata;
                default: rdata = 0;
            endcase
        end
    end

    assign irq = fifo_full;

endmodule
