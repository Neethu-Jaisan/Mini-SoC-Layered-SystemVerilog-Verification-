class generator;

    mailbox #(txn) mbx;
    int verbose;

    function new(mailbox #(txn) m, int v);
        mbx = m;
        verbose = v;
    endfunction

    task run(int count);

        txn t;

        repeat(count) begin
            t = new();
            assert(t.randomize());

            if(verbose)
                $display("[GEN ] T=%0t WR=%0b RD=%0b ADDR=%h DATA=%h",
                          $time, t.wr, t.rd, t.addr, t.data);

            mbx.put(t);
        end

    endtask

endclass
