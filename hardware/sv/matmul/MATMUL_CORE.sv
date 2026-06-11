`include "defines.svh"

module MATMUL_CORE (
    input  logic clock,
    input  logic reset,
    // Control Interface from CONTROLLER.sv
    input  logic valid_in,
    input  logic clear_acc,
    // Data Inputs (Now coming from outside) [cite: 36, 38]
    input  logic [7:0] shared_w,
    input  logic [`NUM_LANES-1:0][7:0] x_vector,
    // External Scale Factors
    input  logic signed [31:0] w_s,    
    input  logic signed [31:0] x_s,    
    // Outputs
    output logic signed [31:0] final_float_out,
    output logic done
);
    // Internal routing for Lane results [cite: 36]
    wire signed [`NUM_LANES-1:0][17:0] lane_results;
    wire [`NUM_LANES-1:0] lane_v_outs;

    // Processing Lanes [cite: 39]
    genvar i;
    generate
        for (i = 0; i < `NUM_LANES; i = i + 1) begin : gen_lanes
            MATMUL lane_inst (
                .clock(clock), 
                .reset(reset), 
                .valid_in(valid_in),
                .w($signed(shared_w)), 
                .x($signed(x_vector[i])),
                .clear_acc(clear_acc), 
                .out(lane_results[i]), 
                .v_out(lane_v_outs[i])
            );
        end
    endgenerate

    // Final Aggregation [cite: 40]
    MASTER_ACCUMULATOR aggregator (
        .clock(clock), 
        .reset(reset), 
        .start_conv(lane_v_outs[0]), 
        .lane_ivals(lane_results), 
        .w_s(w_s), 
        .x_s(x_s),
        .float_out(final_float_out), 
        .done(done)
    );

endmodule