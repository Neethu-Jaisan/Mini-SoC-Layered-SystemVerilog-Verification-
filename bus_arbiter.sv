// ============================================================
// Simple Fixed Priority Arbiter (CPU priority)
// ============================================================

module bus_arbiter(
    input  logic req_cpu,      // CPU request
    input  logic req_dma,      // DMA request
    output logic grant_cpu,    // CPU grant
    output logic grant_dma     // DMA grant
);

    always_comb begin
        if(req_cpu) begin
            grant_cpu = 1;
            grant_dma = 0;
        end
        else if(req_dma) begin
            grant_cpu = 0;
            grant_dma = 1;
        end
        else begin
            grant_cpu = 0;
            grant_dma = 0;
        end
    end

endmodule
