// ============================================================
// testbench.sv
//Mini SoC Layered Testbench
// ============================================================

`timescale 1ns/1ns

module tb;

  // ----------------------------------------------------------
  // Clock
  // ----------------------------------------------------------
  bit clk = 0;
  always #5 clk = ~clk;

  // ----------------------------------------------------------
  // Interface
  // ----------------------------------------------------------
  soc_if vif(clk);

  // ----------------------------------------------------------
  // DUT
  // ----------------------------------------------------------
  mini_soc dut(
    .clk   (clk),
    .rst_n (vif.rst_n),
    .addr  (vif.addr),
    .wdata (vif.wdata),
    .wr_en (vif.wr_en),
    .rd_en (vif.rd_en),
    .rdata (vif.rdata)
  );

  // ==========================================================
  // Transaction
  // ==========================================================

  class soc_txn;

    rand bit [7:0]  addr;
    rand bit [31:0] wdata;
    rand bit        wr_en;
    rand bit        rd_en;

    constraint valid_rw {
      !(wr_en && rd_en);
      wr_en || rd_en;
    }

    constraint valid_addr {
      addr inside {8'h00,8'h04,8'h08,8'h0C};
    }

  endclass


  // ==========================================================
  // Generator
  // ==========================================================

  class generator;

    mailbox #(soc_txn) gen2drv;

    function new(mailbox #(soc_txn) m);
      gen2drv = m;
    endfunction

    task run();
      soc_txn tx;
      repeat(30) begin
        tx = new();
        assert(tx.randomize());
        gen2drv.put(tx);
      end
    endtask

  endclass


  // ==========================================================
  // Driver
  // ==========================================================

  class driver;

    virtual soc_if vif;
    mailbox #(soc_txn) gen2drv;
    semaphore bus_lock;
    event tx_done;

    function new(virtual soc_if vif,
                 mailbox #(soc_txn) m,
                 semaphore s,
                 event e);
      this.vif   = vif;
      gen2drv    = m;
      bus_lock   = s;
      tx_done    = e;
    endfunction

    task run();
      soc_txn tx;

      forever begin
        gen2drv.get(tx);

        bus_lock.get();

        vif.cb.addr  <= tx.addr;
        vif.cb.wdata <= tx.wdata;
        vif.cb.wr_en <= tx.wr_en;
        vif.cb.rd_en <= tx.rd_en;

        @(vif.cb);

        vif.cb.wr_en <= 0;
        vif.cb.rd_en <= 0;

        bus_lock.put();

        -> tx_done;
      end
    endtask

  endclass


  // ==========================================================
  // Monitor
  // ==========================================================

  class monitor;

    virtual soc_if vif;
    mailbox #(soc_txn) mon2sb;

    function new(virtual soc_if vif,
                 mailbox #(soc_txn) m);
      this.vif = vif;
      mon2sb   = m;
    endfunction

    task run();
      soc_txn tx;

      forever begin
        @(posedge vif.clk);

        if(vif.rd_en) begin
          tx = new();
          tx.addr  = vif.addr;
          tx.wdata = vif.rdata;
          mon2sb.put(tx);
        end
      end
    endtask

  endclass


  // ==========================================================
  // Scoreboard (RTL-Accurate Model)
  // ==========================================================

  class scoreboard;

    mailbox #(soc_txn) mon2sb;
    virtual soc_if vif;

    bit [31:0] model_control;
    bit [3:0]  model_gpio;
    bit [31:0] model_counter;
    bit        prev_enable;

    function new(mailbox #(soc_txn) m,
                 virtual soc_if vif);
      mon2sb = m;
      this.vif = vif;

      model_control = 0;
      model_gpio    = 0;
      model_counter = 0;
      prev_enable   = 0;
    endfunction

    task run();

      soc_txn tx;
      bit [31:0] expected;

      forever begin
        @(posedge vif.clk);

        // ------------------------------------
        //  CHECK READS FIRST
        // ------------------------------------
        if(mon2sb.num() > 0) begin
          mon2sb.get(tx);

          case(tx.addr)

            8'h00: expected = model_control;

            8'h04: expected = {28'b0, model_gpio};

            8'h08: expected = model_counter;

            8'h0C: expected = {24'b0,
                               model_gpio,
                               model_control[0],
                               3'b0};

            default: expected = 32'h0;

          endcase

          $display("Read Addr=%0h Data=%0h",
                    tx.addr, tx.wdata);

          if(expected !== tx.wdata) begin
            $error("Mismatch at Addr=%0h Expected=%0h Got=%0h",
                    tx.addr, expected, tx.wdata);
          end
        end

        // ------------------------------------
        //  TRACK WRITES
        // ------------------------------------
        if(vif.wr_en) begin
          case(vif.addr)
            8'h00: model_control = vif.wdata;
            8'h04: model_gpio    = vif.wdata[3:0];
          endcase
        end

        // ------------------------------------
        //  RTL-ACCURATE COUNTER UPDATE
        // ------------------------------------
        if(prev_enable)
          model_counter++;

        prev_enable = model_control[0];

      end

    endtask

  endclass


  // ==========================================================
  // Environment
  // ==========================================================

  class environment;

    generator  gen;
    driver     drv;
    monitor    mon;
    scoreboard sb;

    mailbox #(soc_txn) gen2drv;
    mailbox #(soc_txn) mon2sb;
    semaphore bus_lock;
    event tx_done;

    function new(virtual soc_if vif);

      gen2drv = new();
      mon2sb  = new();
      bus_lock = new(1);

      gen = new(gen2drv);
      drv = new(vif, gen2drv, bus_lock, tx_done);
      mon = new(vif, mon2sb);
      sb  = new(mon2sb, vif);

    endfunction

    task run();
      fork
        gen.run();
        drv.run();
        mon.run();
        sb.run();
      join_none
    endtask

  endclass


  // ==========================================================
  // TEST
  // ==========================================================

  initial begin

    environment env;

    vif.rst_n = 0;
    repeat(5) @(posedge clk);
    vif.rst_n = 1;

    env = new(vif);
    env.run();

    #1000;
    $finish;

  end

endmodule
