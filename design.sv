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


// =======================================================
// FIFO MODULE
// =======================================================
// Parameterized synchronous FIFO
// Used to demonstrate inter-module data flow inside SoC
// =======================================================

module fifo #(parameter WIDTH=32, DEPTH=8)(

    input  logic clk,
    input  logic rst_n,

    // Write side
    input  logic wr_en,
    input  logic rd_en,
    input  logic [WIDTH-1:0] wdata,

    // Read side
    output logic [WIDTH-1:0] rdata,

    output logic full,
    output logic empty
);

    // Memory array
    logic [WIDTH-1:0] mem [DEPTH];

    // Write and read pointers
    logic [$clog2(DEPTH)-1:0] wr_ptr, rd_ptr;

    // Count tracks number of elements
    // One extra bit to detect full condition
    logic [$clog2(DEPTH):0] count;


    // ===================================================
    // Sequential FIFO Logic
    // ===================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if(!rst_n) begin
            // Reset everything
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
            rdata  <= 0;
        end

        else begin

            // -------------------------------
            // WRITE OPERATION
            // -------------------------------
            if(wr_en && !full) begin
                mem[wr_ptr] <= wdata;     // Store data
                wr_ptr <= wr_ptr + 1;     // Move write pointer
            end

            // -------------------------------
            // READ OPERATION
            // -------------------------------
            if(rd_en && !empty) begin
                rdata <= mem[rd_ptr];     // Output data
                rd_ptr <= rd_ptr + 1;     // Move read pointer
            end

            // -------------------------------
            // COUNT MANAGEMENT
            // -------------------------------
            // Increment only if write without read
            if(wr_en && !full && !(rd_en && !empty))
                count <= count + 1;

            // Decrement only if read without write
            else if(rd_en && !empty && !(wr_en && !full))
                count <= count - 1;

            // If both read and write valid → count unchanged
        end
    end

    // Full when count equals DEPTH
    assign full  = (count == DEPTH);

    // Empty when count is zero
    assign empty = (count == 0);

endmodule



// =======================================================
// MINI SoC MODULE
// =======================================================
// Memory-mapped architecture
// Address map:
// 0x00 → Control register
// 0x04 → GPIO register
// 0x08 → Timer register (read-only)
// 0x10 → FIFO write
// 0x14 → FIFO read
// =======================================================

module mini_soc(

    input  logic clk,
    input  logic rst_n,

    // CPU side signals
    input  logic        cpu_wr_en,
    input  logic        cpu_rd_en,
    input  logic [7:0]  cpu_addr,
    input  logic [31:0] cpu_wdata,

    output logic [31:0] cpu_rdata
);

    // ===================================================
    // INTERNAL REGISTERS
    // ===================================================

    logic [31:0] control_reg;  // Bit0 enables timer
    logic [3:0]  gpio_reg;     // Lower 4-bit GPIO
    logic [31:0] timer_reg;    // Free-running timer

    logic [31:0] fifo_rdata;
    logic fifo_full, fifo_empty;


    // ===================================================
    // TIMER LOGIC
    // ===================================================
    // Timer increments only when control_reg[0] = 1

    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n)
            timer_reg <= 0;
        else if(control_reg[0])
            timer_reg <= timer_reg + 1;


    // ===================================================
    // WRITE LOGIC (Memory-mapped write decode)
    // ===================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if(!rst_n) begin
            control_reg <= 0;
            gpio_reg    <= 0;
        end

        else if(cpu_wr_en) begin

            // Address decoding
            case(cpu_addr)

                // Control register write
                8'h00: control_reg <= cpu_wdata;

                // GPIO write (only lower 4 bits used)
                8'h04: gpio_reg <= cpu_wdata[3:0];

                // FIFO write handled separately below

            endcase
        end
    end


    // ===================================================
    // FIFO INSTANTIATION
    // ===================================================
    // Write to 0x10
    // Read from 0x14

    fifo fifo_inst(
        .clk(clk),
        .rst_n(rst_n),

        .wr_en(cpu_wr_en && cpu_addr==8'h10),
        .rd_en(cpu_rd_en && cpu_addr==8'h14),

        .wdata(cpu_wdata),
        .rdata(fifo_rdata),

        .full(fifo_full),
        .empty(fifo_empty)
    );


    // ===================================================
    // READ DECODE LOGIC (Combinational)
    // ===================================================

    logic [31:0] read_next;

    always_comb begin
        case(cpu_addr)

            8'h00: read_next = control_reg;

            8'h04: read_next = {28'd0, gpio_reg};

            8'h08: read_next = timer_reg;

            8'h14: read_next = fifo_rdata;

            // Illegal / unmapped address
            default: read_next = 32'hDEAD_BEEF;

        endcase
    end


    // ===================================================
    // REGISTERED READ OUTPUT
    // ===================================================
    // 1-cycle read latency (synchronous read)

    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n)
            cpu_rdata <= 0;
        else if(cpu_rd_en)
            cpu_rdata <= read_next;

endmodule
