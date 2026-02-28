// ============================================================
// design.sv
// Mini SoC + Interface
// ============================================================

interface soc_if(input bit clk);

  logic rst_n;

  logic [7:0]  addr;
  logic [31:0] wdata;
  logic [31:0] rdata;
  logic wr_en;
  logic rd_en;

  clocking cb @(posedge clk);
    output addr, wdata, wr_en, rd_en;
    input  rdata;
  endclocking

endinterface


// ============================================================
// Mini SoC DUT
// ============================================================

module mini_soc(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  addr,
    input  logic [31:0] wdata,
    input  logic        wr_en,
    input  logic        rd_en,
    output logic [31:0] rdata
);

  // Address Map
  // 0x00 - Control Register
  // 0x04 - GPIO Register
  // 0x08 - Counter Register
  // 0x0C - Status Register

  logic [31:0] control_reg;
  logic [3:0]  gpio_reg;
  logic [31:0] counter_reg;
  logic [31:0] status_reg;

  // Counter logic
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
      counter_reg <= 0;
    else if(control_reg[0])
      counter_reg <= counter_reg + 1;
  end

  // Write logic
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

  // Status aggregation
  always_comb begin
    status_reg = {24'b0, gpio_reg, control_reg[0], 3'b0};
  end

  // Read logic
  always_comb begin
    rdata = 32'h0;
    if(rd_en) begin
      case(addr)
        8'h00: rdata = control_reg;
        8'h04: rdata = {28'b0, gpio_reg};
        8'h08: rdata = counter_reg;
        8'h0C: rdata = status_reg;
      endcase
    end
  end

endmodule
