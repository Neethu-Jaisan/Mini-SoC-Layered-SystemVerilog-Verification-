module tb;

    // ===================================================
    // CLOCK GENERATION
    // ===================================================
    // 10ns clock period (100 MHz)
    // Toggles every 5ns
    bit clk = 0;
    always #5 clk = ~clk;


    // ===================================================
    // INTERFACE INSTANCE
    // ===================================================
    // Connects DUT and testbench using a clean abstraction
    soc_if vif(clk);


    // ===================================================
    // DUT INSTANTIATION
    // ===================================================
    // Interface signals mapped to DUT ports
    mini_soc dut(
        .clk(clk),
        .rst_n(vif.rst_n),
        .cpu_wr_en(vif.wr_en),
        .cpu_rd_en(vif.rd_en),
        .cpu_addr(vif.addr),
        .cpu_wdata(vif.wdata),
        .cpu_rdata(vif.rdata)
    );


    // ===================================================
    // GLOBAL CONTROL VARIABLES
    // ===================================================

    int VERBOSE = 1;      // Controls printing
    int error_count = 0;  // Tracks scoreboard mismatches


    // ===================================================
    // TRANSACTION CLASS
    // ===================================================
    // Represents one bus operation
    // Used for constrained-random stimulus

    class txn;

        rand bit wr;                 // Write enable
        rand bit rd;                 // Read enable
        rand bit [7:0]  addr;        // Address
        rand bit [31:0] data;        // Data payload

        // Ensure only one operation at a time
        constraint op_c {
            wr ^ rd;     // XOR ensures exactly one is high
        }

        // Weighted address distribution
        // Higher weights = more frequent access
        constraint addr_c {
            addr dist {
                8'h00 := 3,      // Control
                8'h04 := 3,      // GPIO
                8'h08 := 2,      // Timer
                8'h10 := 3,      // FIFO write
                8'h14 := 3,      // FIFO read
                [8'h20:8'h2F] := 1  // Illegal range (coverage)
            };
        }

    endclass


    // ===================================================
    // COMMUNICATION MECHANISMS
    // ===================================================

    mailbox #(txn) gen2drv = new();   // Generator → Driver
    mailbox #(txn) mon2sb  = new();   // Monitor → Scoreboard

    semaphore bus_lock = new(1);
    // Ensures only one driver access at a time
    // (Scalable if multiple agents exist)

    event drv_done;
    // Used to synchronize monitor sampling


    // ===================================================
    // GENERATOR
    // ===================================================
    // Creates randomized transactions

    class generator;

        mailbox #(txn) mbx;

        function new(mailbox #(txn) m);
            mbx = m;
        endfunction

        task run(int count);

            txn t;

            repeat(count) begin
                t = new();

                // Randomization with constraints
                assert(t.randomize());

                if(VERBOSE)
                    $display("[GEN ] T=%0t WR=%0b RD=%0b ADDR=%h DATA=%h",
                              $time, t.wr, t.rd, t.addr, t.data);

                mbx.put(t);  // Send to driver
            end
        endtask

    endclass


    // ===================================================
    // DRIVER
    // ===================================================
    // Converts transactions into pin-level activity

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

                mbx.get(t);   // Get transaction
                lock.get();   // Acquire bus access

                @(posedge vif.clk);

                // Drive signals
                vif.addr  <= t.addr;
                vif.wdata <= t.data;
                vif.wr_en <= t.wr;
                vif.rd_en <= t.rd;

                if(VERBOSE)
                    $display("[DRV ] T=%0t WR=%0b RD=%0b ADDR=%h WDATA=%h",
                              $time, t.wr, t.rd, t.addr, t.data);

                // Hold for 1 cycle
                @(posedge vif.clk);

                // Deassert control
                vif.wr_en <= 0;
                vif.rd_en <= 0;

                -> done;   // Notify monitor
                lock.put();
            end
        endtask

    endclass


    // ===================================================
    // MONITOR
    // ===================================================
    // Passive observer — never drives signals
    // Samples DUT output after driver transaction

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

                @(done);               // Wait for driver completion
                @(posedge vif.clk);    // Sample next cycle

                t = new();

                t.addr = vif.addr;
                t.data = vif.rdata;
                t.wr   = vif.wr_en;
                t.rd   = vif.rd_en;

                if(VERBOSE)
                    $display("[MON ] T=%0t ADDR=%h RDATA=%h",
                              $time, t.addr, t.data);

                mbx.put(t);  // Send to scoreboard
            end
        endtask

    endclass


    // ===================================================
    // SCOREBOARD (Cycle-Accurate Reference Model)
    // ===================================================
    // Mirrors DUT behavior in pure software model

    class scoreboard;

        mailbox #(txn) mbx;

        // Reference model variables
        bit [31:0] control_ref;
        bit [3:0]  gpio_ref;
        bit [31:0] timer_ref;
        bit [31:0] fifo_q[$];  // Dynamic queue models FIFO

        function new(mailbox #(txn) m);
            mbx = m;
        endfunction

        task reset_model();
            control_ref = 0;
            gpio_ref = 0;
            timer_ref = 0;
            fifo_q.delete();
        endtask


        task run();

            txn t;

            forever begin

                mbx.get(t);

                // Reset handling
                if(!vif.rst_n) begin
                    reset_model();
                    continue;
                end

                // WRITE model update
                if(t.wr) begin
                    case(t.addr)
                        8'h00: control_ref = t.data;
                        8'h04: gpio_ref    = t.data[3:0];
                        8'h10: fifo_q.push_back(t.data);
                    endcase
                end

                // READ checking
                if(t.rd) begin

                    bit [31:0] exp;

                    case(t.addr)
                        8'h00: exp = control_ref;
                        8'h04: exp = {28'd0,gpio_ref};
                        8'h08: exp = timer_ref;
                        8'h14: exp = (fifo_q.size()) ?
                                      fifo_q.pop_front() : 0;
                        default: exp = 32'hDEAD_BEEF;
                    endcase

                    if(VERBOSE)
                        $display("[SB  ] T=%0t ADDR=%h EXP=%h GOT=%h",
                                  $time, t.addr, exp, t.data);

                    if(exp !== t.data) begin
                        $error("Mismatch Addr=%h Exp=%h Got=%h",
                               t.addr, exp, t.data);
                        error_count++;
                    end
                end

                // Cycle-accurate timer update
                @(posedge vif.clk);
                if(control_ref[0])
                    timer_ref++;

            end
        endtask

    endclass


    // ===================================================
    // FUNCTIONAL COVERAGE
    // ===================================================

    covergroup cg @(posedge clk);

        coverpoint vif.addr;    // Address coverage
        coverpoint vif.wr_en;   // Write coverage
        coverpoint vif.rd_en;   // Read coverage

    endgroup

    cg coverage = new();


    // ===================================================
    // ASSERTION
    // ===================================================
    // Ensures protocol correctness

    property no_simultaneous_wr_rd;
        @(posedge clk)
        !(vif.wr_en && vif.rd_en);
    endproperty

    assert property(no_simultaneous_wr_rd);


    // ===================================================
    // TEST CONTROL
    // ===================================================

    initial begin

        generator  gen;
        driver     drv;
        monitor    mon;
        scoreboard sb;

        // Initial reset
        vif.rst_n = 0;
        vif.wr_en = 0;
        vif.rd_en = 0;

        repeat(5) @(posedge clk);
        vif.rst_n = 1;

        // Create components
        gen = new(gen2drv);
        drv = new(gen2drv, vif, bus_lock, drv_done);
        mon = new(mon2sb,  vif, drv_done);
        sb  = new(mon2sb);

        // Start all components
        fork
            gen.run(200);
            drv.run();
            mon.run();
            sb.run();
        join_none

        // Mid-test reset to verify robustness
        #1500;
        vif.rst_n = 0;
        repeat(3) @(posedge clk);
        vif.rst_n = 1;

        #5000;

        if(error_count == 0)
            $display("========= TEST PASSED =========");
        else
            $display("========= TEST FAILED =========");

        $display("Functional Coverage = %0.2f%%",
                 coverage.get_coverage());

        $finish;
    end

endmodule
