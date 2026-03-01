class monitor;

    mailbox #(txn) mbx;
    virtual soc_if vif;
    event done;
    int verbose;

    function new(mailbox #(txn) m,
                 virtual soc_if v,
                 event e,
                 int vbs);
        mbx = m;
        vif = v;
        done = e;
        verbose = vbs;
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

            if(verbose)
                $display("[MON ] T=%0t ADDR=%h RDATA=%h",
                          $time, t.addr, t.data);

            mbx.put(t);
        end

    endtask

endclass
