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

    // =====================================================
    // TRANSACTION
    // =====================================================

    class txn;
        rand bit wr;
        rand bit rd;
        rand bit [7:0] addr;
        rand bit [31:0] data;

        constraint c1 { !(wr && rd); wr || rd; }

        constraint c2 {
            if(wr) addr inside {8'h00,8'h04,8'h10};
            if(rd) addr inside {8'h00,8'h04,8'h08,8'h14};
        }
    endclass


    // =====================================================
    // MAILBOXES / SYNC
    // =====================================================

    mailbox #(txn) gen2drv = new();
    mailbox #(txn) mon2sb  = new();

    semaphore bus_lock = new(1);
    event drv_done;


    // =====================================================
    // GENERATOR
    // =====================================================

    class generator;
        mailbox #(txn) mbx;

        function new(mailbox #(txn) m);
            mbx = m;
        endfunction

        task run(int count);
            txn t;
            repeat(count) begin
                t = new();
                assert(t.randomize());
                $display("[GEN ] T=%0t WR=%0b RD=%0b ADDR=%h DATA=%h",
                         $time, t.wr, t.rd, t.addr, t.data);
                mbx.put(t);
            end
        endtask
    endclass


    // =====================================================
    // DRIVER
    // =====================================================

    class driver;
        mailbox #(txn) mbx;
        virtual soc_if vif;
        semaphore lock;
        event done;

        function new(mailbox #(txn) m,
                     virtual soc_if v,
                     semaphore s,
                     event e);
            mbx = m;
            vif = v;
            lock = s;
            done = e;
        endfunction

        task run();
            txn t;
            forever begin
                mbx.get(t);
                lock.get();

                @(posedge vif.clk);
                vif.addr  <= t.addr;
                vif.wdata <= t.data;
                vif.wr_en <= t.wr;
                vif.rd_en <= t.rd;

                $display("[DRV ] T=%0t WR=%0b RD=%0b ADDR=%h WDATA=%h",
                         $time, t.wr, t.rd, t.addr, t.data);

                @(posedge vif.clk);
                vif.wr_en <= 0;
                vif.rd_en <= 0;

                -> done;
                lock.put();
            end
        endtask
    endclass


    // =====================================================
    // MONITOR
    // =====================================================

    class monitor;
        mailbox #(txn) mbx;
        virtual soc_if vif;
        event done;

        function new(mailbox #(txn) m,
                     virtual soc_if v,
                     event e);
            mbx = m;
            vif = v;
            done = e;
        endfunction

        task run();
            txn t;
            forever begin
                @(done);
                @(posedge vif.clk);

                t = new();
                t.addr = vif.addr;
                t.data = vif.rdata;
                t.wr   = vif.wr_en;
                t.rd   = vif.rd_en;

                $display("[MON ] T=%0t ADDR=%h RDATA=%h",
                         $time, t.addr, t.data);

                mbx.put(t);
            end
        endtask
    endclass


    // =====================================================
    // SCOREBOARD
    // =====================================================

    class scoreboard;
        mailbox #(txn) mbx;

        bit [31:0] control_ref;
        bit [3:0]  gpio_ref;
        bit [31:0] timer_ref;
        bit [31:0] fifo_q[$];

        function new(mailbox #(txn) m);
            mbx = m;
        endfunction

        task run();
            txn t;
            forever begin
                mbx.get(t);

                if(t.wr) begin
                    case(t.addr)
                        8'h00: control_ref = t.data;
                        8'h04: gpio_ref    = t.data[3:0];
                        8'h10: fifo_q.push_back(t.data);
                    endcase
                    $display("[SB  ] WRITE ADDR=%h DATA=%h",
                             t.addr, t.data);
                end

                if(t.rd) begin
                    bit [31:0] exp;
                    case(t.addr)
                        8'h00: exp = control_ref;
                        8'h04: exp = {28'd0,gpio_ref};
                        8'h08: exp = timer_ref;
                        8'h14: exp = (fifo_q.size()) ?
                                      fifo_q.pop_front() : 0;
                    endcase

                    $display("[SB  ] READ  ADDR=%h EXP=%h GOT=%h",
                             t.addr, exp, t.data);

                    if(exp !== t.data)
                        $error("Mismatch Addr=%h Exp=%h Got=%h",
                               t.addr, exp, t.data);
                end

                if(control_ref[0])
                    timer_ref++;
            end
        endtask
    endclass


    // =====================================================
    // TEST
    // =====================================================

    initial begin

        generator  gen;
        driver     drv;
        monitor    mon;
        scoreboard sb;

        vif.rst_n = 0;
        vif.wr_en = 0;
        vif.rd_en = 0;

        repeat(5) @(posedge clk);
        vif.rst_n = 1;

        gen = new(gen2drv);
        drv = new(gen2drv, vif, bus_lock, drv_done);
        mon = new(mon2sb,  vif, drv_done);
        sb  = new(mon2sb);

        fork
            gen.run(20);    // small number for readable debug
            drv.run();
            mon.run();
            sb.run();
        join_none

        #5000;
        $finish;
    end

endmodule
