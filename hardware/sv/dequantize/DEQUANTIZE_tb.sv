`timescale 1ns/1ps

module DEQUANTIZE_tb;

    localparam int BW    = 32;
    localparam int LANES = 4;
    
    // Test Signals
    logic                   clk;
    logic                   rst_n;
    logic                   en;
    logic [31:0]            scale_in;
    logic [(LANES*8)-1:0]   q_data;
    logic [(LANES*BW)-1:0]  data_out;
    logic                   vld_out;

    // Instantiate Unit Under Test
    DEQUANTIZE #(.BW(BW), .LANES(LANES)) uut (.*);

    // Clock Generation
    initial clk = 0;
    always #5 clk = ~clk;

    // --- Verification Task ---
    task drive_sample(input logic [31:0] scale, input logic [7:0] val0, val1, val2, val3);
        scale_in <= scale;
        q_data   <= {val3, val2, val1, val0};
        en       <= 1'b1;
        @(posedge clk);
        en       <= 1'b0;
    endtask

    initial begin
        // 1. Initialize & Reset
        rst_n = 0; en = 0; scale_in = 0; q_data = 0;
        #20 rst_n = 1;
        repeat(2) @(posedge clk);

        $display("\n--- Starting Dequantization Tests ---");

        // 2. Test Case 1: Small Scale (Q24)
        // Scale = 0.5 (0x00800000 in Q24)
        $display("[TB] Test 1: Scale = 0.5 (Q24)");
        drive_sample(32'h00800000, 8'd10, 8'd20, 8'd40, 8'd100);
        
        // 3. Test Case 2: Max Scale (Q24)
        // Scale = 1.0 (0x01000000 in Q24)
        $display("[TB] Test 2: Scale = 1.0 (Q24)");
        drive_sample(32'h01000000, 8'd10, 8'd20, 8'd40, 8'd100);

        // 4. Test Case 3: Random Large Scale
        // Scale = 2.75 (0x02C00000 in Q24)
        $display("[TB] Test 3: Scale = 2.75 (Q24)");
        drive_sample(32'h02C00000, 8'd5, 8'd10, 8'd15, 8'd20);

        repeat(5) @(posedge clk);
        $display("--- Dequantization Tests Finished ---");
        $finish;
    end

    // Monitor for results
    always @(negedge clk) begin
        if (vld_out) begin
            $display("[RESULT] Time: %0t", $time);
            $display("         Scale: %h", scale_in);
            $display("         L0: %d | L1: %d | L2: %d | L3: %d", 
                     data_out[31:0], data_out[63:32], data_out[95:64], data_out[127:96]);
        end
    end

endmodule