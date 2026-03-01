// ============================================================
// testbench.sv
// Layered Testbench
// ============================================================

`timescale 1ns/1ns

module tb;

    // Clock
    bit clk = 0;
    always #5 clk = ~clk;

    // Interface
    soc_if vif(clk);

    // DUT
    mini_soc dut(
        .clk(clk),
        .rst_n(vif.rst_n),

        .cpu_wr_en(vif.wr_en),
        .cpu_rd_en(vif.rd_en),
        .cpu_addr(vif.addr),
        .cpu_wdata(vif.wdata),
        .cpu_rdata(vif.rdata),

        .dma_wr_en(1'b0),
        .dma_rd_en(1'b0),
        .dma_addr(8'h00),
        .dma_wdata(32'h0),
        .dma_rdata(),

        .irq()
    );

    // ========================================================
    // TRANSACTION
    // ========================================================

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
            addr inside {8'h00,8'h04,8'h08,8'h10,8'h14};
        }
    endclass

    // ========================================================
    // GENERATOR
    // ========================================================

    class generator;

        mailbox #(soc_txn) gen2drv;

        function new(mailbox #(soc_txn) m);
            gen2drv = m;
        endfunction

        task run();
            soc_txn tx;
            repeat(40) begin
                tx = new();
                assert(tx.randomize());
                gen2drv.put(tx);
            end
        endtask

    endclass

    // ========================================================
    // DRIVER
    // ========================================================

    class driver;

        virtual soc_if vif;
        mailbox #(soc_txn) gen2drv;

        function new(virtual soc_if vif,
                     mailbox #(soc_txn) m);
            this.vif = vif;
            gen2drv = m;
        endfunction

        task run();
            soc_txn tx;

            forever begin
                gen2drv.get(tx);

                vif.cb.addr  <= tx.addr;
                vif.cb.wdata <= tx.wdata;
                vif.cb.wr_en <= tx.wr_en;
                vif.cb.rd_en <= tx.rd_en;

                @(vif.cb);

                vif.cb.wr_en <= 0;
                vif.cb.rd_en <= 0;
            end
        endtask

    endclass

    // ========================================================
    // MONITOR
    // ========================================================

  class monitor;

    virtual soc_if vif;
    mailbox #(soc_txn) mon2sb;

    function new(virtual soc_if vif,
                 mailbox #(soc_txn) m);
        this.vif = vif;
        mon2sb = m;
    endfunction

    task run();
        soc_txn tx;
        forever begin
            @(posedge vif.clk);  // Use real clock

            if(vif.rd_en) begin  // Read interface signals directly
                tx = new();
                tx.addr  = vif.addr;
                tx.wdata = vif.rdata;
                mon2sb.put(tx);
            end
        end
    endtask

endclass

    // ========================================================
    // SCOREBOARD
    // ========================================================

    class scoreboard;

        mailbox #(soc_txn) mon2sb;

        function new(mailbox #(soc_txn) m);
            mon2sb = m;
        endfunction

        task run();
            soc_txn tx;
            forever begin
                mon2sb.get(tx);
                $display("Read Addr=%h Data=%h", tx.addr, tx.wdata);
            end
        endtask

    endclass

    // ========================================================
    // ENVIRONMENT
    // ========================================================

    class environment;

        generator gen;
        driver drv;
        monitor mon;
        scoreboard sb;

        mailbox #(soc_txn) gen2drv;
        mailbox #(soc_txn) mon2sb;

        function new(virtual soc_if vif);
            gen2drv = new();
            mon2sb  = new();

            gen = new(gen2drv);
            drv = new(vif, gen2drv);
            mon = new(vif, mon2sb);
            sb  = new(mon2sb);
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

    // ========================================================
    // TEST
    // ========================================================

    initial begin

        environment env;   // FIXED declaration

        vif.rst_n = 0;
        repeat(5) @(posedge clk);
        vif.rst_n = 1;

        env = new(vif);    // FIXED construction
        env.run();

        #2000;
        $finish;

    end

endmodule
