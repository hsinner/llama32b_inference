`include "defines.svh"

module MASTER_ACCUMULATOR (
    input  logic clock,
    input  logic reset,
    input  logic start_conv,           
    input  logic signed [`NUM_LANES-1:0][17:0] lane_ivals, 
    input  logic signed [31:0] w_s,           
    input  logic signed [31:0] x_s,           
    output logic signed [31:0] float_out,
    output logic done
);

    typedef enum logic [1:0] { IDLE, ACCUMULATE, CONVERT } state_t;
    state_t state;
    logic signed [31:0] total_group_int; 

    always_ff @(posedge clock) begin
        if (reset) begin
            state <= IDLE;
            total_group_int <= 32'sd0;
            float_out <= 32'sd0;
            done <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start_conv) begin
                        $display("[%0t ns] MASTER_ACC: State -> ACCUMULATE (Triggered by Lane 0)", $time);
                        state <= ACCUMULATE;
                    end
                end

                ACCUMULATE: begin
                    automatic logic signed [31:0] temp_sum = 0;
                    
                    for (int i = 0; i < `NUM_LANES; i++) begin
                        // Debug: Print individual lane values to see if any are 'x'
                        if (lane_ivals[i] === 18'shxxxx) begin
                            $display("[%0t ns] MASTER_ACC_DEBUG: Lane %0d is X!", $time, i);
                        end
                        temp_sum = temp_sum + $signed(lane_ivals[i]);
                    end
                    
                    total_group_int <= temp_sum;
                    $display("[%0t ns] MASTER_ACC_DEBUG: Final Sum of all %0d lanes = %d", $time, `NUM_LANES, temp_sum);
                    state <= CONVERT;
                end

                CONVERT: begin
                    // Check if scales are 'x'
                    if (w_s === 32'shxxxxxxxx || x_s === 32'shxxxxxxxx) begin
                        $display("[%0t ns] MASTER_ACC_ERROR: w_s or x_s is UNINITIALIZED (x)!", $time);
                    end
                    
                    float_out <= total_group_int * w_s * x_s;
                    $display("[%0t ns] MASTER_ACC_DEBUG: Scaling %d * %d * %d = %d", 
                             $time, total_group_int, w_s, x_s, (total_group_int * w_s * x_s));
                    done <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule