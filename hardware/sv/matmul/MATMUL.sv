module MATMUL (
    input  logic clock,
    input  logic reset,
    input  logic valid_in,
    input  logic signed [7:0] w,
    input  logic signed [7:0] x,
    input  logic clear_acc,
    output logic signed [17:0] out,
    output logic v_out
);

    logic signed [17:0] accumulator;

always_ff @(posedge clock) begin
    if (reset) begin
        accumulator <= 18'sd0;
        out         <= 18'sd0;
        v_out       <= 1'b0;
    end else begin
        if (valid_in === 1'b1) begin
            // Track every single multiplication to find where 'x' originates
            $display("[%0t ns] LANE_ACC_DEBUG: acc=%0d + (%0d * %0d)", 
                     $time, $signed(accumulator), $signed(w), $signed(x));
            
            accumulator <= $signed(accumulator) + ($signed(w) * $signed(x));
        end

        if (clear_acc === 1'b1) begin
            automatic logic signed [17:0] result = $signed(accumulator) + ($signed(w) * $signed(x));
            out   <= result;
            v_out <= 1'b1;
            
            accumulator <= 18'sd0;
            $display("[%0t ns] MATMUL_LANE_OUT: Value %d is now sitting on the bus.", $time, result);
        end else begin
            v_out <= 1'b0;
        end
    end
end

endmodule