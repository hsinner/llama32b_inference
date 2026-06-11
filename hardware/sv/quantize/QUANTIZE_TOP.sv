// File: QUANTIZE_TOP.sv
module QUANTIZE_TOP #(
    parameter int BW = 32,
    parameter int LANES = 4
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   start,
    input  logic [(LANES*BW)-1:0]  data_in,
    output logic                   ready,
    output logic [(LANES*8)-1:0]   data_out,
    output logic                   vld_out
);

    typedef enum logic [1:0] {IDLE, PASS1, WAIT, PASS2} state_t;
    state_t state, next_state;

    logic [31:0] captured_scale;
    logic [31:0] scale_wire;
    logic        vld_p1, en_p1, en_p2;
    logic [4:0]  count;

    QUANTIZE #(.BW(BW), .LANES(LANES)) discovery_unit (
        .clk(clk), .rst_n(rst_n), .en(en_p1),
        .data_in(data_in), .wmax_out(), .scale_out(scale_wire), .valid(vld_p1)
    );

    QUANTIZE_EXEC #(.BW(BW), .LANES(LANES)) exec_unit (
        .clk(clk), .rst_n(rst_n), .en(en_p2),
        .scale_in(captured_scale), .data_in(data_in),
        .data_out(data_out), .vld_out(vld_out)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            captured_scale <= '0;
            count <= '0;
        end else begin
            state <= next_state;
            
            // CRITICAL: We must latch scale_wire when vld_p1 is high.
            // In QUANTIZE.sv, scale_out and valid are only high for ONE cycle.
            if (vld_p1) begin
                captured_scale <= scale_wire;
            end

            if (state == PASS1 || state == PASS2) count <= count + 1'b1;
            else                                   count <= 5'd0;
        end
    end

    always_comb begin
        next_state = state;
        en_p1 = 0; en_p2 = 0; ready = 0;
        case (state)
            IDLE: begin
                ready = 1;
                if (start) next_state = PASS1;
            end
            PASS1: begin
                en_p1 = 1;
                if (count == 15) next_state = WAIT;
            end
            WAIT: begin
                // In your QUANTIZE.sv, valid (vld_p1) comes 2 cycles AFTER 
                // the last data cycle. We must wait for it here.
                if (vld_p1) next_state = PASS2;
            end
            PASS2: begin
                en_p2 = 1;
                if (count == 15) next_state = IDLE;
            end
        endcase
    end
endmodule