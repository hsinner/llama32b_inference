// File: DEQUANTIZE.sv
// Description: Converts 8-bit quantized values back to higher precision (BW) 
// using the formula: x[i] = q[i] * scale
module DEQUANTIZE #(
    parameter int BW    = 32, // Target Bit Width (e.g., 32-bit fixed/float)
    parameter int LANES = 4   // Elements per clock cycle
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   en,         // High when q_data is valid
    input  logic [31:0]            scale_in,   // The scale factor for the current group
    input  logic [(LANES*8)-1:0]   q_data,     // 8-bit quantized inputs
    output logic [(LANES*BW)-1:0]  data_out,   // Dequantized outputs
    output logic                   vld_out     // High when data_out is valid
);

    // Internal signals for pipelined multiplication
    logic [(LANES*BW)-1:0] dequant_res;
    logic                  vld_reg;

    genvar i;
    generate
        for (i = 0; i < LANES; i++) begin : gen_dequant
            // Perform the multiplication: q[i] * scale
            // Note: If scale_in is Q24, the result can be shifted to match target BW
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    data_out[(i*BW) +: BW] <= '0;
                end else if (en) begin
                    // Multiplication logic
                    // We cast the 8-bit q_data to 64-bit for safe multiplication
                    data_out[(i*BW) +: BW] <= (64'(q_data[(i*8) +: 8]) * 64'(scale_in)) >> 24;
                end
            end
        end
    endgenerate

    // Pipeline the valid signal to match the 1-cycle multiplication delay
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) vld_reg <= 1'b0;
        else        vld_reg <= en;
    end

    assign vld_out = vld_reg;

endmodule