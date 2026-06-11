module CONTROLLER #(
    parameter LANES = 16,
    parameter ACCUM_CYCLES = 4
)(
    input  logic clock,
    input  logic reset,
    input  logic start,
    output logic [11:0] rd_addr,
    output logic valid_in,
    output logic clear_acc,
    output logic done,
    output logic busy       // Restored to fix instantiation error
);

    typedef enum logic [1:0] {IDLE, COMPUTE, FINAL_STEP, FINISH} state_t;
    state_t state;
    
    logic [7:0] cycle_count;

    // Busy logic: We are busy if we aren't in IDLE
    assign busy = (state != IDLE);

    always_ff @(posedge clock) begin
        if (reset) begin
            state       <= IDLE;
            rd_addr     <= 12'd0;
            valid_in    <= 1'b0;
            clear_acc   <= 1'b0;
            done        <= 1'b0;
            cycle_count <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state    <= COMPUTE;
                        rd_addr  <= 12'd0;
                        valid_in <= 1'b1;
                        cycle_count <= 8'd0;
                    end
                end

                COMPUTE: begin
                    // ACCUM_CYCLES = 4. 
                    // Move to FINAL_STEP when count is 2 (the 3rd cycle).
                    if (cycle_count == ACCUM_CYCLES - 2) begin 
                        state <= FINAL_STEP;
                    end
                    cycle_count <= cycle_count + 1;
                    rd_addr     <= rd_addr + 1;
                    valid_in    <= 1'b1;
                end

                FINAL_STEP: begin
                    // Pulse clear_acc while HOLDING the last valid address (Addr 3)
                    clear_acc <= 1'b1;
                    valid_in  <= 1'b1; 
                    state     <= FINISH;
                end

                FINISH: begin
                    clear_acc <= 1'b0;
                    valid_in  <= 1'b0;
                    done      <= 1'b1;
                    state     <= IDLE;
                end
            endcase
        end
    end
endmodule