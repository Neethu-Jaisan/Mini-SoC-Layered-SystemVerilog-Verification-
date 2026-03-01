`timescale 1ns/1ns

interface soc_if(input logic clk);
    logic rst_n;
    logic wr_en;
    logic rd_en;
    logic [7:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
endinterface



// =====================================================
// FIFO
// =====================================================

module fifo #(parameter WIDTH=32, DEPTH=8)(
    input  logic clk,
    input  logic rst_n,
    input  logic wr_en,
    input  logic rd_en,
    input  logic [WIDTH-1:0] wdata,
    output logic [WIDTH-1:0] rdata,
    output logic full,
    output logic empty
);

    logic [WIDTH-1:0] mem [DEPTH];
    logic [$clog2(DEPTH)-1:0] wr_ptr, rd_ptr;
    logic [$clog2(DEPTH):0] count;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
            rdata  <= 0;
        end
        else begin
            if(wr_en && !full) begin
                mem[wr_ptr] <= wdata;
                wr_ptr <= wr_ptr + 1;
                $display("[FIFO] T=%0t WRITE Data=%h Ptr=%0d",
                         $time, wdata, wr_ptr);
            end

            if(rd_en && !empty) begin
                rdata <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1;
                $display("[FIFO] T=%0t READ  Data=%h Ptr=%0d",
                         $time, mem[rd_ptr], rd_ptr);
            end

            if(wr_en && !full && !(rd_en && !empty))
                count <= count + 1;
            else if(rd_en && !empty && !(wr_en && !full))
                count <= count - 1;
        end
    end

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

endmodule



// =====================================================
// MINI SOC
// =====================================================

module mini_soc(
    input  logic clk,
    input  logic rst_n,
    input  logic        cpu_wr_en,
    input  logic        cpu_rd_en,
    input  logic [7:0]  cpu_addr,
    input  logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata
);

    logic [31:0] control_reg;
    logic [3:0]  gpio_reg;
    logic [31:0] timer_reg;

    logic [31:0] fifo_rdata;
    logic fifo_full, fifo_empty;

    // TIMER
    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n)
            timer_reg <= 0;
        else if(control_reg[0]) begin
            timer_reg <= timer_reg + 1;
            $display("[DUT ] T=%0t TIMER=%0d", $time, timer_reg+1);
        end

    // WRITE
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            control_reg <= 0;
            gpio_reg <= 0;
        end
        else if(cpu_wr_en) begin
            case(cpu_addr)
                8'h00: begin
                    control_reg <= cpu_wdata;
                    $display("[DUT ] T=%0t WRITE CONTROL=%h",
                             $time, cpu_wdata);
                end
                8'h04: begin
                    gpio_reg <= cpu_wdata[3:0];
                    $display("[DUT ] T=%0t WRITE GPIO=%h",
                             $time, cpu_wdata[3:0]);
                end
            endcase
        end
    end

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

    // REGISTERED READ (1-cycle latency)

    logic [31:0] read_next;

    always_comb begin
        case(cpu_addr)
            8'h00: read_next = control_reg;
            8'h04: read_next = {28'd0,gpio_reg};
            8'h08: read_next = timer_reg;
            8'h14: read_next = fifo_rdata;
            default: read_next = 0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n)
            cpu_rdata <= 0;
        else if(cpu_rd_en) begin
            cpu_rdata <= read_next;
            $display("[DUT ] T=%0t READ ADDR=%h RDATA=%h",
                     $time, cpu_addr, read_next);
        end

endmodule
