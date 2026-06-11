`timescale 1ns/1ps

module QUANTIZE_TOP_tb;

    localparam int BW = 32;
    localparam int LANES = 4;
    localparam int TOTAL_ELEMENTS = 64;
    localparam int CYCLES_PER_PASS = 16; 

    logic                   clk;
    logic                   rst_n;
    logic                   start;
    logic [(LANES*BW)-1:0]  data_in;
    logic                   ready;
    logic [(LANES*8)-1:0]   data_out;
    logic                   vld_out;

    // Instantiate Top Level
    QUANTIZE_TOP #(.BW(BW), .LANES(LANES)) uut (.*);

    // Clock Generation
    initial clk = 0;
    always #5 clk = ~clk;

    // --- Streaming Task ---
    // Sends 16 cycles of data to match CYCLES_PER_GROUP in QUANTIZE.sv
    task stream_pass(input int seed);
        for (int i = 0; i < CYCLES_PER_PASS; i++) begin
            data_in[(0*BW)+:BW] <= (i*4 + 0) + seed;
            data_in[(1*BW)+:BW] <= (i*4 + 1) + seed;
            data_in[(2*BW)+:BW] <= (i*4 + 2) + seed;
            data_in[(3*BW)+:BW] <= (i*4 + 3) + seed;
            @(posedge clk);
        end
        data_in <= '0;
    endtask

    // --- Monitor Block ---
    initial begin
        forever begin
            @(negedge clk);
            if (vld_out) begin
                $display("[DATA_OUT] Time: %0t | L0: %d | L1: %d | L2: %d | L3: %d", 
                         $time, data_out[7:0], data_out[15:8], data_out[23:16], data_out[31:24]);
            end
        end
    end

    // --- Main Test Sequence ---
    initial begin
        // 1. Reset Phase
        rst_n = 0; start = 0; data_in = '0;
        #50 rst_n = 1; 
        
        // Ensure the FSM is in IDLE and ready is high
        wait(ready == 1'b1);
        repeat(2) @(posedge clk);
        
        $display("\n--- Starting 2-Pass Test Sequence ---");
        
        // 2. Trigger Pass 1 (Discovery)
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        $display(">> Streaming Pass 1...");
        stream_pass(0); // Max will be 63

        // 3. Wait for Latching
        // The FSM moves to WAIT, then PASS2 once discovery_unit.valid pulses
        wait(uut.state == 2'b11); // 2'b11 is PASS2
        $display(">> Scale Latched. Streaming Pass 2...");

        // 4. Trigger Pass 2 (Execution)
        // Note: The FSM automatically enters PASS2, so we just feed the data
        stream_pass(0); 

        // 5. Cleanup
        repeat(10) @(posedge clk);
        $display("--- Test Bench Finished ---");
        $finish;
    end

endmodule