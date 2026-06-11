module BRAM #(parameter ADDR_WIDTH = 12, DATA_WIDTH = 8) (
    input  logic clock,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic wr_en,
    input  logic [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout
);
    // Use the synthesis attribute to ensure it stays as a BRAM block
    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [(2**ADDR_WIDTH)-1:0];

    always_ff @(posedge clock) begin
        if (wr_en) begin
            $display("[%0t ns] BRAM WRITE: Addr=%0d, Data=%0h", $time, wr_addr, din);
            mem[wr_addr] <= din;
        end
        // Synchronous read for BRAM inference
        dout <= mem[rd_addr];
    end
endmodule