`timescale 1ns/1ps

module QUANTIZE_TOP_tb;

    localparam int BW = 32;
    localparam int LANES = 4;
    localparam int CYCLES_PER_PASS = 16; 

    logic                   clk;
    logic                   rst_n;
    logic                   start;
    logic [(LANES*BW)-1:0]  data_in;
    logic                   ready;
    logic [(LANES*8)-1:0]   data_out;
    logic                   vld_out;

    // Buffer to store the random data from Pass 1 to repeat it in Pass 2
    logic [(LANES*BW)-1:0]  data_buffer [0:CYCLES_PER_PASS-1];

    QUANTIZE_TOP #(.BW(BW), .LANES(LANES)) uut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    // --- Task: Generate and Stream Random Data ---
    task stream_random_data(input bit capture);
        for (int i = 0; i < CYCLES_PER_PASS; i++) begin
            if (capture) begin
                // Randomize each lane with values up to the full 31-bit range
                for (int l = 0; l < LANES; l++) begin
                    data_buffer[i][(l*BW)+:BW] = $urandom_range(0, 32'h7FFFFFFF);
                end
            end
            data_in <= data_buffer[i];
            @(posedge clk);
        end
        data_in <= '0;
    endtask

    initial begin
        // Initialize
        rst_n = 0; start = 0; data_in = '0;
        #50 rst_n = 1;

        // Run 5 different random test iterations
        for (int test_num = 1; test_num <= 5; test_num++) begin
            $display("\n--- Starting Random Test Iteration %0d ---", test_num);
            
            wait(ready == 1'b1);
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            // Pass 1: Discovery (Generate new random data)
            $display("[TB] Streaming Pass 1 (Discovery)...");
            stream_random_data(1'b1); 

            // Pass 2: Execution (Replay the exact same data)
            wait(uut.state == 2'b11); // Wait for PASS2 state
            $display("[TB] Scale Latched. Replaying Pass 2 (Execution)...");
            stream_random_data(1'b0);

            repeat(5) @(posedge clk);
        end

        $display("\n--- All Random Tests Finished ---");
        $finish;
    end

    // Monitor for output validation
    always @(negedge clk) begin
        if (vld_out) begin
            $display("[OUT] Time: %0t | Scale: %h | L0_Quant: %d", $time, uut.captured_scale, data_out[7:0]);
        end
    end

endmodule