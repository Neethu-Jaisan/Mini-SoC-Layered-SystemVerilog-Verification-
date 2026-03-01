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

    int VERBOSE = 1;

    mailbox #(txn) gen2drv = new();
    mailbox #(txn) mon2sb  = new();
    semaphore bus_lock = new(1);
    event drv_done;

    initial begin

        generator  gen;
        driver     drv;
        monitor    mon;
        scoreboard sb;
        coverage   cov;

        vif.rst_n = 0;
        vif.wr_en = 0;
        vif.rd_en = 0;

        repeat(5) @(posedge clk);
        vif.rst_n = 1;

        gen = new(gen2drv, VERBOSE);
        drv = new(gen2drv, vif, bus_lock, drv_done, VERBOSE);
        mon = new(mon2sb,  vif, drv_done, VERBOSE);
        sb  = new(mon2sb,  vif, VERBOSE);
        cov = new(vif);

        fork
            gen.run(200);
            drv.run();
            mon.run();
            sb.run();
        join_none

        #1500;
        vif.rst_n = 0;
        repeat(3) @(posedge clk);
        vif.rst_n = 1;

        #5000;

        if(sb.error_count == 0)
            $display("========= TEST PASSED =========");
        else
            $display("========= TEST FAILED =========");

        $display("Functional Coverage = %0.2f%%",
                 cov.get_cov());

        $finish;
    end

endmodule
