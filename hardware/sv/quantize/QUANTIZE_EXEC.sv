// File: QUANTIZE_EXEC.sv (with Debug Prints)
module QUANTIZE_EXEC #(
    parameter int BW    = 32,
    parameter int LANES = 4
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic [31:0]            scale_in,   
    input  logic                   en,         
    input  logic [(LANES*BW)-1:0]  data_in,    
    output logic [(LANES*8)-1:0]   data_out,   
    output logic                   vld_out     
);

    localparam logic [63:0] ROUND_AMT = 64'h00800000; 

    genvar i;
    generate
        for (i = 0; i < LANES; i++) begin : gen_quant
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    data_out[(i*8)+7 : i*8] <= '0; 
                end else if (en) begin
                    $display("[DEBUG EXEC] Lane %0d: Data=%d * Scale=%h", i, data_in[(i*BW) +: BW], scale_in);
                    data_out[(i*8)+7 : i*8] <= ((64'(data_in[(i*BW) +: BW]) * 64'(scale_in)) + ROUND_AMT) >> 24; 
                end
            end
        end
    endgenerate

    logic vld_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) vld_reg <= 1'b0; 
        else        vld_reg <= en; 
    end
    assign vld_out = vld_reg; 

endmodule