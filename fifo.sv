// ============================================================
// FIFO Module (Simple synchronous FIFO)
// ============================================================

module fifo #(
    parameter WIDTH = 32,        // Data width
    parameter DEPTH = 8          // FIFO depth
)(
    input  logic clk,            // Clock
    input  logic rst_n,          // Active low reset
    input  logic wr_en,          // Write enable
    input  logic rd_en,          // Read enable
    input  logic [WIDTH-1:0] wdata, // Write data
    output logic [WIDTH-1:0] rdata, // Read data
    output logic full,           // FIFO full flag
    output logic empty           // FIFO empty flag
);

    // Memory array for FIFO storage
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // Write and read pointers
    logic [$clog2(DEPTH):0] wr_ptr, rd_ptr;
    logic [$clog2(DEPTH+1):0] count; // Element counter

    // Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ptr <= 0;
        end
        else if(wr_en && !full) begin
            mem[wr_ptr] <= wdata;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // Read logic
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

    // Counter logic
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            count <= 0;
        else begin
            case({wr_en && !full, rd_en && !empty})
                2'b10: count <= count + 1; // Write only
                2'b01: count <= count - 1; // Read only
                default: count <= count;   // No change
            endcase
        end
    end

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

endmodule
