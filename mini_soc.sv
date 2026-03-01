// ============================================================
// MINI SoC TOP
// ============================================================

module mini_soc(
    input  logic clk,
    input  logic rst_n,

    // CPU Master Interface
    input  logic        cpu_wr_en,
    input  logic        cpu_rd_en,
    input  logic [7:0]  cpu_addr,
    input  logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata,

    // DMA Master Interface
    input  logic        dma_wr_en,
    input  logic        dma_rd_en,
    input  logic [7:0]  dma_addr,
    input  logic [31:0] dma_wdata,
    output logic [31:0] dma_rdata,

    output logic irq
);

    // Internal shared bus signals
    logic        wr_en, rd_en;
    logic [7:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    // Arbiter signals
    logic grant_cpu, grant_dma;

    // Instantiate arbiter
    bus_arbiter arb(
        .req_cpu(cpu_wr_en | cpu_rd_en),
        .req_dma(dma_wr_en | dma_rd_en),
        .grant_cpu(grant_cpu),
        .grant_dma(grant_dma)
    );

    // Bus MUX selection
    always_comb begin
        if(grant_cpu) begin
            wr_en = cpu_wr_en;
            rd_en = cpu_rd_en;
            addr  = cpu_addr;
            wdata = cpu_wdata;
            cpu_rdata = rdata;
            dma_rdata = 0;
        end
        else if(grant_dma) begin
            wr_en = dma_wr_en;
            rd_en = dma_rd_en;
            addr  = dma_addr;
            wdata = dma_wdata;
            dma_rdata = rdata;
            cpu_rdata = 0;
        end
        else begin
            wr_en = 0;
            rd_en = 0;
            addr  = 0;
            wdata = 0;
            cpu_rdata = 0;
            dma_rdata = 0;
        end
    end

    // Internal registers
    logic [31:0] control_reg;
    logic [3:0]  gpio_reg;
    logic [31:0] timer_reg;
    logic [31:0] status_reg;

    // Timer logic
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            timer_reg <= 0;
        else if(control_reg[0])
            timer_reg <= timer_reg + 1;
    end

    // FIFO instance
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

    // Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            control_reg <= 0;
            gpio_reg <= 0;
        end
        else if(wr_en) begin
            case(addr)
                8'h00: control_reg <= wdata;
                8'h04: gpio_reg <= wdata[3:0];
            endcase
        end
    end

    // Status register aggregation
    always_comb begin
        status_reg = {24'b0, fifo_full, fifo_empty,
                      gpio_reg, control_reg[0]};
    end

    // Read logic
    always_comb begin
        rdata = 32'h0;
        if(rd_en) begin
            case(addr)
                8'h00: rdata = control_reg;
                8'h04: rdata = {28'b0, gpio_reg};
                8'h08: rdata = timer_reg;
                8'h0C: rdata = status_reg;
                8'h14: rdata = fifo_rdata;
                default: rdata = 0;
            endcase
        end
    end

    // Interrupt generation
    assign irq = fifo_full | (timer_reg == 32'hFFFF_FFFF);

endmodule
