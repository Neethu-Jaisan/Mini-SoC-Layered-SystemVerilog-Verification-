class driver;

    mailbox #(txn) mbx;
    virtual soc_if vif;
    semaphore lock;
    event done;
    int verbose;

    function new(mailbox #(txn) m,
                 virtual soc_if v,
                 semaphore s,
                 event e,
                 int vbs);
        mbx = m;
        vif = v;
        lock = s;
        done = e;
        verbose = vbs;
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

            if(verbose)
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
