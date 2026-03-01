// ============================================================
// testbench.sv
// Final Stable Transaction-Based Layered Testbench
// ============================================================

`timescale 1ns/1ns

module tb;

    bit clk = 0;
    always #5 clk = ~clk;

    soc_if vif(clk);

    mini_soc dut(
        .clk(clk),
        .rst_n(vif.rst_n),
        .cpu_wr_en(vif.wr_en),
        .cpu_rd_en(vif.rd_en),
        .cpu_addr(vif.addr),
        .cpu_wdata(vif.wdata),
        .cpu_rdata(vif.rdata)
    );

    // ========================================================
    // TRANSACTION
    // ========================================================

    class soc_txn;
        bit [7:0]  addr;
        bit [31:0] wdata;
        bit        wr_en;
        bit        rd_en;
    endclass


    // ========================================================
    // GENERATOR (Deterministic)
    // ========================================================

    class generator;

        mailbox #(soc_txn) gen2drv;

        function new(mailbox #(soc_txn) m);
            gen2drv = m;
        endfunction

        task run();

            soc_txn tx;

            // Enable timer
            tx = new();
            tx.addr = 8'h00;
            tx.wdata = 32'h1;
            tx.wr_en = 1;
            tx.rd_en = 0;
            gen2drv.put(tx);

            // Read timer 5 times
            repeat(5) begin
                tx = new();
                tx.addr = 8'h08;
                tx.wr_en = 0;
                tx.rd_en = 1;
                gen2drv.put(tx);
            end

            // FIFO write
            repeat(4) begin
                tx = new();
                tx.addr = 8'h10;
                tx.wdata = $urandom;
                tx.wr_en = 1;
                tx.rd_en = 0;
                gen2drv.put(tx);
            end

            // FIFO read
            repeat(4) begin
                tx = new();
                tx.addr = 8'h14;
                tx.wr_en = 0;
                tx.rd_en = 1;
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
        mailbox #(soc_txn) drv2sb;

        function new(virtual soc_if vif,
                     mailbox #(soc_txn) g2d,
                     mailbox #(soc_txn) d2s);
            this.vif = vif;
            gen2drv = g2d;
            drv2sb = d2s;
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
                @(vif.cb);

                vif.cb.wr_en <= 0;
                vif.cb.rd_en <= 0;

                @(vif.cb);

                if(tx.wr_en)
                    drv2sb.put(tx);

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
                     mailbox #(soc_txn) m2s);
            this.vif = vif;
            mon2sb = m2s;
        endfunction

        task run();

            soc_txn tx;
            bit rd_prev = 0;

            forever begin
                @(posedge vif.clk);

                if(vif.rd_en && !rd_prev) begin
                    @(posedge vif.clk);

                    tx = new();
                    tx.addr  = vif.addr;
                    tx.wdata = vif.rdata;
                    mon2sb.put(tx);
                end

                rd_prev = vif.rd_en;
            end
        endtask

    endclass


    // ========================================================
    // SCOREBOARD
    // ========================================================

    class scoreboard;

        mailbox #(soc_txn) mon2sb;
        mailbox #(soc_txn) drv2sb;
        virtual soc_if vif;

        bit [31:0] model_control;
        bit [3:0]  model_gpio;
        bit [31:0] model_timer;
        bit [31:0] fifo_q[$];

        function new(mailbox #(soc_txn) m2s,
                     mailbox #(soc_txn) d2s,
                     virtual soc_if vif);
            mon2sb = m2s;
            drv2sb = d2s;
            this.vif = vif;
        endfunction

        task run();

            soc_txn tx;
            bit [31:0] expected;

            forever begin
                @(posedge vif.clk);

                if(!vif.rst_n) begin
                    model_control = 0;
                    model_gpio    = 0;
                    model_timer   = 0;
                    fifo_q.delete();
                end

                // Write tracking
                if(drv2sb.num() > 0) begin
                    drv2sb.get(tx);
                    case(tx.addr)
                        8'h00: model_control = tx.wdata;
                        8'h04: model_gpio    = tx.wdata[3:0];
                        8'h10: fifo_q.push_back(tx.wdata);
                    endcase
                end

                // Timer model
                if(model_control[0])
                    model_timer++;

                // Read checking
                if(mon2sb.num() > 0) begin
                    mon2sb.get(tx);

                    case(tx.addr)
                        8'h00: expected = model_control;
                        8'h04: expected = {28'b0, model_gpio};
                        8'h08: expected = model_timer;
                        8'h14: begin
                            if(fifo_q.size() > 0)
                                expected = fifo_q.pop_front();
                            else
                                expected = 0;
                        end
                        default: expected = 0;
                    endcase

                    $display("READ Addr=%h Expected=%h Got=%h",
                              tx.addr, expected, tx.wdata);

                    if(expected !== tx.wdata)
                        $error("MISMATCH at Addr=%h Expected=%h Got=%h",
                                tx.addr, expected, tx.wdata);
                end

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
        mailbox #(soc_txn) drv2sb;

        function new(virtual soc_if vif);

            gen2drv = new();
            mon2sb  = new();
            drv2sb  = new();

            gen = new(gen2drv);
            drv = new(vif, gen2drv, drv2sb);
            mon = new(vif, mon2sb);
            sb  = new(mon2sb, drv2sb, vif);

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

        environment env;

        vif.rst_n = 0;
        repeat(5) @(posedge clk);
        vif.rst_n = 1;

        env = new(vif);
        env.run();

        #2000;
        $finish;

    end

endmodule
