`include "RMSNORM_SVH.svh"

module RMSNorm (
    input  logic clock,
    input  logic reset,
    input  logic start,
    
    // Dynamic Precision & Dimension Configurations
    input  logic [`FLAG_WIDTH-1:0] int_width_flag, // Controls binary point position
    input  logic [`SIZE_WIDTH-1:0] size_in,        // Dynamic loop bound (e.g., 64 or 3072)
    
    // Data Interfaces
    input  logic signed [`TOTAL_WIDTH-1:0] x_in,
    input  logic signed [`TOTAL_WIDTH-1:0] weight_in,
    input  logic valid_in,
    
    // System Handshakes
    output logic signed [`TOTAL_WIDTH-1:0] norm_out,
    output logic valid_out,
    output logic busy
);

    // Dynamic fractional tracking bit width
    logic [4:0] frac_width;
    assign frac_width = `TOTAL_WIDTH - int_width_flag;

    // FSM States declaration
    typedef enum logic [1:0] {
        INIT, 
        ACCUMULATOR, 
        CORDIC, 
        NORM_SCALER
    } state_t;
    state_t state;

    // ----------------------------------------------------------------
    // INTERNAL REGISTERS & STORAGE (BRAM BUFFER)
    // ----------------------------------------------------------------
    logic signed [31:0] product_sq_reg;
    logic signed [31:0] product_wx_reg; 
    logic signed [`ACCUM_WIDTH-1:0] accumulator;
    logic [`SIZE_WIDTH-1:0] element_count;
    logic valid_in_d1;
    logic signed [`ACCUM_WIDTH-1:0] mean_square;

    // High-Efficiency Internal Memory Array
    logic signed [31:0] internal_bram [0:3071];
    logic [`SIZE_WIDTH-1:0] scale_read_ptr;

    // Fixed-Point Square Root Processing Registers
    logic signed [`ACCUM_WIDTH-1:0] cordic_x; // Holds the radicand remainder
    logic signed [`ACCUM_WIDTH-1:0] cordic_y; // Accumulates the root result
    logic [5:0]                      cordic_iter;
    logic [47:0]                     sqrt_rem;

    // Scaler Output Stage registers
    logic signed [31:0] final_scale;
    logic signed [31:0] scaler_stored_wx;

    // ----------------------------------------------------------------
    // PIPELINE ALIGNMENT & SYNTAX RESOLUTION NETS
    // ----------------------------------------------------------------
    // 2-bit shift register to track synchronous RAM read latency
    logic [1:0] valid_pipe;

    // Intermediate net to perform arithmetic legally before slicing (Fixes vlog-13069)
    logic signed [63:0] scaler_product;
    assign scaler_product = ($signed(scaler_stored_wx) * $signed(final_scale)) >>> (frac_width * 2);

    assign busy = (state != INIT) || start;

    // ----------------------------------------------------------------
    // STAGE 1 PIPELINE: MULTIPLICATION LAYER
    // ----------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (reset) begin
            product_sq_reg <= 32'sd0;
            product_wx_reg <= 32'sd0;
        end else if (state == ACCUMULATOR && valid_in) begin
            product_sq_reg <= $signed(x_in) * $signed(x_in);
            product_wx_reg <= $signed(weight_in) * $signed(x_in); 
        end
    end

    // ----------------------------------------------------------------
    // MASTER SEQUENCER STATE MACHINE
    // ----------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (reset) begin
            state            <= INIT;
            accumulator      <= '0;
            element_count    <= '0;
            valid_in_d1      <= 1'b0;
            mean_square      <= '0;
            cordic_x         <= '0;
            cordic_y         <= '0;
            cordic_iter      <= '0;
            sqrt_rem         <= '0;
            final_scale      <= 32'sd0;
            scale_read_ptr   <= '0;
            norm_out         <= '0;
            valid_out        <= 1'b0;
            scaler_stored_wx <= 32'sd0;
            valid_pipe       <= 2'b00;
        end else begin
            valid_in_d1 <= valid_in;

            case (state)
                INIT: begin
                    valid_out      <= 1'b0;
                    cordic_iter    <= '0;
                    scale_read_ptr <= '0;
                    valid_pipe     <= 2'b00;
                    if (start) begin
                        accumulator   <= '0;
                        element_count <= '0;
                        state         <= ACCUMULATOR;
                        $display("[RTL INIT] Configuration: Total Bits: %0d, Frac Bits: %0d, Run Size: %0d", 
                                 `TOTAL_WIDTH, (`TOTAL_WIDTH - int_width_flag), size_in);
                    end
                end

                ACCUMULATOR: begin
                    if (valid_in_d1) begin
                        accumulator <= accumulator + product_sq_reg;
                        internal_bram[element_count] <= product_wx_reg;
                        $display("[RTL ACCUM] Item %0d/%0d saved. W*X Hex: 0x%0h, Real Float Accum: %f", 
                                 (element_count + 1), size_in, product_wx_reg,
                                 real'($signed(accumulator + product_sq_reg)) / (2.0 ** (frac_width * 2)));
                        element_count <= element_count + 1;
                    end

                    if (element_count == size_in) begin
                        mean_square <= accumulator / $signed({1'b0, size_in});
                        state       <= CORDIC;
                    end
                end

                CORDIC: begin
                    if (cordic_iter == 6'd0) begin
                        // Initialize Synthesizable Restoring Square Root Structure
                        cordic_x    <= mean_square; 
                        cordic_y    <= '0;          
                        sqrt_rem    <= '0;
                        cordic_iter <= 6'd1;
                    end 
                    else if (cordic_iter <= 6'd24) begin
                        // Deterministic Radix-2 Square Root execution loop (processing 2 bits per cycle)
                        automatic logic [47:0] next_rem;
                        next_rem = {sqrt_rem[45:0], cordic_x[49 - 2*cordic_iter -: 2]};
                        
                        if (next_rem >= {cordic_y[21:0], 2'b01}) begin
                            sqrt_rem <= next_rem - {cordic_y[21:0], 2'b01};
                            cordic_y <= {cordic_y[22:0], 1'b1};
                        end else begin
                            sqrt_rem <= next_rem;
                            cordic_y <= {cordic_y[22:0], 1'b0};
                        end
                        cordic_iter <= cordic_iter + 1;
                    end 
                    else begin
                        // Value of cordic_y now contains accurate fixed-point integer RMS root
                        if (cordic_y != 0) begin
                            // Pre-scale numerator to Q(frac_width) format to guarantee flawless fixed division alignment
                            final_scale <= (64'sd1 << (frac_width * 2)) / cordic_y;
                        end else begin
                            final_scale <= 32'sd0;
                        end
                        state <= NORM_SCALER;
                    end
                end

                NORM_SCALER: begin
                    // 1. Pipeline Control & Address Generation
                    if (scale_read_ptr < size_in) begin
                        scaler_stored_wx <= internal_bram[scale_read_ptr];
                        scale_read_ptr   <= scale_read_ptr + 1;
                        valid_pipe       <= {valid_pipe[0], 1'b1}; // Shift in active tracking bit
                    end else begin
                        valid_pipe       <= {valid_pipe[0], 1'b0}; // Drain pipeline array
                    end

                    // 2. Data Path Extraction (Reads continuous net safely to prevent truncation shifts)
                    norm_out  <= scaler_product[`TOTAL_WIDTH-1:0];
                    valid_out <= valid_pipe[1]; 
                    
                    if (valid_pipe[1]) begin
                        $display("[RTL NORM SCALER] Element Output: norm_out code = 0x%0h", scaler_product[`TOTAL_WIDTH-1:0]);
                    end
                    
                    // 3. Synchronous Termination Gate
                    if (valid_out && !valid_pipe[1]) begin
                        state     <= INIT;
                        valid_out <= 1'b0;
                    end
                end
                
                default: state <= INIT;
            endcase
        end
    end

endmodule