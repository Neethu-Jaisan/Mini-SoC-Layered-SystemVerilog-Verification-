class coverage;

    virtual soc_if vif;
    covergroup cg @(posedge vif.clk);

        coverpoint vif.addr;
        coverpoint vif.wr_en;
        coverpoint vif.rd_en;

    endgroup

    function new(virtual soc_if v);
        vif = v;
        cg = new();
    endfunction

    function real get_cov();
        return cg.get_coverage();
    endfunction

endclass
