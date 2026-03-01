// ============================================================
// design.sv
// Mini SoC DUT (Timer + GPIO + FIFO)
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

    clocking cb @(posedge clk);
        output wr_en, rd_en, addr, wdata;
        input  rdata;
    endclocking

endinterface


// ============================================================
// FIFO (Correct & Stable)
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

    logic [$clog2(DEPTH)-1:0] wr_ptr, rd_ptr;
    logic [$clog2(DEPTH+1):0] count;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
            rdata  <= 0;
        end
        else begin

            // Write
            if(wr_en && !full) begin
                mem[wr_ptr] <= wdata;
                wr_ptr <= (wr_ptr + 1) % DEPTH;
            end

            // Read
            if(rd_en && !empty) begin
                rdata <= mem[rd_ptr];
                rd_ptr <= (rd_ptr + 1) % DEPTH;
            end

            // Count update
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
// MINI SoC
// ============================================================

module mini_soc(
    input  logic clk,
    input  logic rst_n,

    input  logic        cpu_wr_en,
    input  logic        cpu_rd_en,
    input  logic [7:0]  cpu_addr,
    input  logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata
);

    logic wr_en, rd_en;
    logic [7:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    assign wr_en = cpu_wr_en;
    assign rd_en = cpu_rd_en;
    assign addr  = cpu_addr;
    assign wdata = cpu_wdata;
    assign cpu_rdata = rdata;

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

    // Write registers
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

    // Read mux
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

endmodule
