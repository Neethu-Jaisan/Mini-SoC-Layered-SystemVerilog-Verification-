class scoreboard;

    mailbox #(txn) mbx;
    virtual soc_if vif;

    bit [31:0] control_ref;
    bit [3:0]  gpio_ref;
    bit [31:0] timer_ref;
    bit [31:0] fifo_q[$];

    int error_count;
    int verbose;

    function new(mailbox #(txn) m,
                 virtual soc_if v,
                 int vbs);
        mbx = m;
        vif = v;
        verbose = vbs;
        error_count = 0;
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

            if(!vif.rst_n) begin
                reset_model();
                continue;
            end

            if(t.wr) begin
                case(t.addr)
                    8'h00: control_ref = t.data;
                    8'h04: gpio_ref    = t.data[3:0];
                    8'h10: fifo_q.push_back(t.data);
                endcase
            end

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

                if(verbose)
                    $display("[SB  ] T=%0t ADDR=%h EXP=%h GOT=%h",
                              $time, t.addr, exp, t.data);

                if(exp !== t.data) begin
                    $error("Mismatch Addr=%h Exp=%h Got=%h",
                           t.addr, exp, t.data);
                    error_count++;
                end
            end

            @(posedge vif.clk);
            if(control_ref[0])
                timer_ref++;
        end

    endtask

endclass
