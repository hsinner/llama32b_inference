// File: QUANTIZE.sv (with Debug Prints)
module QUANTIZE #(
    parameter int GS         = 64, 
    parameter int BW         = 32, 
    parameter int LANES      = 4   
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   en,           
    input  logic [(LANES*BW)-1:0]  data_in,      

    output logic [BW-1:0]          wmax_out,     
    output logic [BW-1:0]          scale_out,    
    output logic                   valid         
);
    localparam int CYCLES_PER_GROUP = GS / LANES; 
    logic [3:0] cycle_cnt; 
    logic       wmax_ready; 

    logic [BW-2:0] abs_lane [LANES-1:0]; 
    logic [BW-2:0] l01_max, l23_max, cycle_max; 
    logic [BW-2:0] running_max; 

    genvar i;
    generate
        for (i = 0; i < LANES; i++) begin : gen_abs
            assign abs_lane[i] = data_in[(i*BW) + (BW-2) : (i*BW)];
        end
    endgenerate

    always_comb begin
        l01_max   = (abs_lane[0] > abs_lane[1]) ? abs_lane[0] : abs_lane[1];
        l23_max   = (abs_lane[2] > abs_lane[3]) ? abs_lane[2] : abs_lane[3]; 
        cycle_max = (l01_max > l23_max) ? l01_max : l23_max; 
    end

    // --- STAGE 1: Discovery Debugging ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running_max <= '0;
            cycle_cnt   <= '0; 
            wmax_out    <= '0;
            wmax_ready  <= 1'b0; 
        end else if (en) begin
            if (cycle_max > running_max) running_max <= cycle_max; 
            
            if (cycle_cnt == (CYCLES_PER_GROUP - 1)) begin 
                wmax_out    <= {1'b0, (cycle_max > running_max ? cycle_max : running_max)}; 
                wmax_ready  <= 1'b1; 
                running_max <= '0; 
                cycle_cnt   <= '0; 
                $display("[DEBUG QUANT] PASS 1 DONE. Final wmax = %d at time %0t", (cycle_max > running_max ? cycle_max : running_max), $time);
            end else begin
                cycle_cnt   <= cycle_cnt + 1'b1; 
                wmax_ready  <= 1'b0; 
            end
        end else begin
            wmax_ready <= 1'b0; 
        end
    end

    // --- STAGE 2: Math Debugging ---
    logic [50:0] scale_accum; 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scale_accum <= '0; 
            scale_out   <= '0; 
            valid       <= 1'b0; 
        end else if (wmax_ready) begin 
            $display("[DEBUG QUANT] Math Triggered! Input wmax: %d", wmax_out);
            scale_accum <= (wmax_out[30:0] << 17) + (wmax_out[30:0] << 10) + 
                           (wmax_out[30:0] << 4) - wmax_out[30:0]; 
            valid       <= 1'b0; 
        end else if (scale_accum != '0) begin
            scale_out <= scale_accum[31:0];
            valid       <= 1'b1; 
            $display("[DEBUG QUANT] Valid Pulse! scale_out = %h (from accum %h)", scale_accum[49:24], scale_accum);
            scale_accum <= '0; 
        end else begin
            valid       <= 1'b0; 
        end
    end
endmodule