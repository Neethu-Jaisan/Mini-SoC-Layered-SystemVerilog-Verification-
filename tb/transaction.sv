class txn;

    rand bit wr;
    rand bit rd;
    rand bit [7:0]  addr;
    rand bit [31:0] data;

    // Only one operation allowed
    constraint op_c {
        wr ^ rd;
    }

    // Weighted address distribution
    constraint addr_c {
        addr dist {
            8'h00 := 3,
            8'h04 := 3,
            8'h08 := 2,
            8'h10 := 3,
            8'h14 := 3,
            [8'h20:8'h2F] := 1
        };
    }

endclass
