`timescale 1ns/1ps
`include "RMSNORM_SVH.svh"

module tb_RMSNorm;

    // Testbench Drivers
    logic clock;
    logic reset;
    logic start;
    logic [`FLAG_WIDTH-1:0] int_width_flag;
    logic [`SIZE_WIDTH-1:0] size_in;
    logic signed [`TOTAL_WIDTH-1:0] x_in;
    logic signed [`TOTAL_WIDTH-1:0] weight_in;
    logic valid_in;

    // Monitor Outputs
    logic signed [`TOTAL_WIDTH-1:0] norm_out;
    logic valid_out;
    logic busy;

    // Instantiate Device Under Test (DUT)
    RMSNorm uut (
        .clock(clock),
        .reset(reset),
        .start(start),
        .int_width_flag(int_width_flag),
        .size_in(size_in),
        .x_in(x_in),
        .weight_in(weight_in),
        .valid_in(valid_in),
        .norm_out(norm_out),
        .valid_out(valid_out),
        .busy(busy)
    );

    // Clock Generator (100 MHz clock -> 10ns period)
    always #5 clock = ~clock;

    // Simulation Configuration Bounds
    localparam TEST_SIZE = 64;
    
    // Test Vectors Arrays
    logic signed [`TOTAL_WIDTH-1:0] test_vector[TEST_SIZE];
    logic signed [`TOTAL_WIDTH-1:0] test_weights[TEST_SIZE];

    // Reference variables for tracking math validation 
    real real_x;
    real sum_of_squares = 0.0;
    real mean_square_ideal = 0.0;
    real rms_scalar_ideal = 0.0;
    real ideal_output;

    initial begin
        // ------------------------------------------------------------
        // 1. SETUP & SYSTEM PRECISION PARAMETERS
        // ------------------------------------------------------------
        clock = 0;
        reset = 1;
        start = 0;
        int_width_flag = 4'd8; // Operating under explicit Q8.8
        size_in = TEST_SIZE;
        x_in = 16'sd0;
        weight_in = 16'sd0;
        valid_in = 0;

        // Generate input distribution dataset within steady convergence limits
        for (int i = 0; i < TEST_SIZE; i++) begin
            test_vector[i]  = $urandom_range(16'h0A00, 16'h0100); // Positive non-zero numbers
            test_weights[i] = 16'h0100; // Hardcoding scale weight to exactly 1.0 (256 in Q8.8)
            
            // Mirror calculation using ideal software reals
            real_x = real'(test_vector[i]) / 256.0;
            sum_of_squares = sum_of_squares + (real_x * real_x);
        end
        
        mean_square_ideal = sum_of_squares / real'(TEST_SIZE);
        if (mean_square_ideal > 0) begin
            rms_scalar_ideal = 1.0 / $sqrt(mean_square_ideal);
        end

        $display("[TB REFERENCE MODEL] Behavioral targets calculated:");
        $display("  -> Sum of Squares: %f", sum_of_squares);
        $display("  -> Mean Square:    %f", mean_square_ideal);
        $display("  -> Scalar Multiplier (1/sqrt): %f\n", rms_scalar_ideal);

        // De-assert system reset
        repeat (4) @(posedge clock);
        reset = 0;
        @(posedge clock);

        // ------------------------------------------------------------
        // 2. PASS 1: FILLING THE ENGINE AND BRAM BUFFER
        // ------------------------------------------------------------
        $display("[TB EVENT] Launching engine start pulse.");
        start = 1;
        @(posedge clock);
        start = 0;

        $display("[TB EVENT] Streaming input elements into module.");
        for (int i = 0; i < TEST_SIZE; i++) begin
            x_in     = test_vector[i];
            weight_in = test_weights[i];
            valid_in = 1;
            @(posedge clock);
        end
        
        // Return interface wires to idle
        x_in     = 16'sd0;
        weight_in = 16'sd0;
        valid_in = 0;

        // ------------------------------------------------------------
        // 3. CORDIC CALCULATION PHASE
        // ------------------------------------------------------------
        // Wait gracefully while the internal state machine crunches CORDIC iterations
        while (uut.state == uut.CORDIC) begin
            @(posedge clock);
        end
        $display("[TB EVENT] CORDIC phase completed. Scale factors locked.");

        // ------------------------------------------------------------
        // 4. STREAMING PASS 2: CAPTURING PIPELINED BRAM OUTPUTS
        // ------------------------------------------------------------
        $display("[TB EVENT] Entering streaming capture loop phase...");
        
        // Wait for the pipeline delay tail to assert the first valid output
        if (!valid_out) begin
            @(posedge valid_out);
        end

        // Extract and verify all 64 items as they travel out of the component
        for (int out_idx = 0; out_idx < TEST_SIZE; out_idx++) begin
            // Calculate what the absolute floating-point value should look like
            ideal_output = (real'(test_vector[out_idx]) / 256.0) * (real'(test_weights[out_idx]) / 256.0) * rms_scalar_ideal;

            $display("[TB OUTPUT CAPTURE] Item %0d/64 -> HW Hex: 0x%0h | HW Real: %f | Ideal Model Float: %f", 
                     (out_idx + 1), 
                     norm_out, 
                     real'(norm_out) / 256.0, 
                     ideal_output);
            
            // Step to the next clock edge to sample the next streaming item
            @(posedge clock);
        end

        $display("\n[TB EVENT] Stream transaction block complete. Finalizing simulation.");
        repeat (10) @(posedge clock);
        $finish;
    end

endmodule