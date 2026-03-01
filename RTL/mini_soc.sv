

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
