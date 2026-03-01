
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

