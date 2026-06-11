`timescale 1ns/1ps

module QUANTIZE_tb;

    // Parameters
    localparam int GS    = 64;
    localparam int BW    = 32;
    localparam int LANES = 4;
    localparam int CYCLES = GS / LANES;

    // Signals
    logic                   clk;
    logic                   rst_n;
    logic                   en;
    logic [(LANES*BW)-1:0]  data_in;
    logic [BW-1:0]          wmax_out;
    logic [BW-1:0]          scale_out;
    logic                   valid;

    // UUT Instance
    QUANTIZE #(.GS(GS), .BW(BW), .LANES(LANES)) uut (.*);

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Test Procedure
    initial begin
        rst_n = 0; en = 0; data_in = '0;
        #20 rst_n = 1; #20;

        $display("\n--- Starting Randomized Stress Test (10 Iterations) ---");
        
        repeat (10) begin
            run_random_group();
        end

        $display("\nRandomized Testing Complete.");
        $finish;
    end

    // Task to generate 64 random numbers and check the hardware result
    task run_random_group();
        logic [31:0] test_data [GS-1:0];
        logic [31:0] expected_max;
        logic [31:0] expected_scale;
        
        expected_max = 0;

        // 1. Generate local "Golden" data
        for (int i = 0; i < GS; i++) begin
            test_data[i] = $urandom_range(0, 50000); // Test range up to 50k
            if (test_data[i] > expected_max) expected_max = test_data[i];
        end
        
        // Golden Scaling Logic: (max * 132111) >> 24
        expected_scale = (64'(expected_max) * 132111) >> 24;

        // 2. Drive the UUT
        @(posedge clk);
        en <= 1;
        for (int i = 0; i < CYCLES; i++) begin
            data_in[31:0]   <= test_data[i*4 + 0];
            data_in[63:32]  <= test_data[i*4 + 1];
            data_in[95:64]  <= test_data[i*4 + 2];
            data_in[127:96] <= test_data[i*4 + 3];
            @(posedge clk);
        end
        en <= 0;
        data_in <= '0;

        // 3. Wait for Hardware Result and Compare
        wait(valid);
        if (wmax_out == expected_max && scale_out == expected_scale) begin
            $display("[PASS] Max: %d | Scale: %d", wmax_out, scale_out);
        end else begin
            $display("[FAIL] Expected Max: %d, Got: %d | Expected Scale: %d, Got: %d", 
                      expected_max, wmax_out, expected_scale, scale_out);
        end
        #20;
    endtask

endmodule