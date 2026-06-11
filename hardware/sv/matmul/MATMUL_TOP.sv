`include "defines.svh"

module MATMUL_TOP (
    input  logic clock,
    input  logic reset,
    input  logic start_op,
    input  logic [`BRAM_ADDR_WIDTH-1:0] wr_addr,
    input  logic wr_en,
    input  logic [(`NUM_LANES*8)+7:0] din, 
    input  logic signed [31:0] w_s,    
    input  logic signed [31:0] x_s,    
    output logic signed [31:0] final_float_out,
    output logic valid_out,
    output logic controller_busy
);

    // Internal Control Signals [cite: 43]
    logic [`BRAM_ADDR_WIDTH-1:0] ctrl_rd_addr;
    logic ctrl_valid_in;
    logic ctrl_clear_acc;

    // Data Busses [cite: 35, 36]
    wire [7:0] shared_w;
    wire [`NUM_LANES-1:0][7:0] x_vector;

    // Instance of CONTROLLER [cite: 44]
    CONTROLLER brain (
        .clock(clock),
        .reset(reset),
        .start(start_op),
        .rd_addr(ctrl_rd_addr),
        .valid_in(ctrl_valid_in),
        .clear_acc(ctrl_clear_acc),
        .busy(controller_busy)
    );

    // --- BRAM INSTANTIATIONS MOVED HERE --- [cite: 36, 38]
    
    // Weight Storage
    BRAM #(.ADDR_WIDTH(`BRAM_ADDR_WIDTH), .DATA_WIDTH(8)) weight_bram (
        .clock(clock), 
        .rd_addr(ctrl_rd_addr), 
        .wr_addr(wr_addr),
        .wr_en(wr_en), 
        .din(din[7:0]), 
        .dout(shared_w)
    );

    // Activation Storage
    genvar i;
    generate
        for (i = 0; i < `NUM_LANES; i = i + 1) begin : gen_top_brams
            BRAM #(.ADDR_WIDTH(`BRAM_ADDR_WIDTH), .DATA_WIDTH(8)) act_bram_inst (
                .clock(clock), 
                .rd_addr(ctrl_rd_addr), 
                .wr_addr(wr_addr),
                .wr_en(wr_en), 
                .din(din[(i+1)*8 +: 8]), 
                .dout(x_vector[i])
            );
        end
    endgenerate

    // Instance of MATMUL_CORE (Now receiving BRAM data) [cite: 45]
    MATMUL_CORE engine (
        .clock(clock),
        .reset(reset),
        .valid_in(ctrl_valid_in),
        .clear_acc(ctrl_clear_acc),
        .shared_w(shared_w),
        .x_vector(x_vector),
        .w_s(w_s),
        .x_s(x_s),
        .final_float_out(final_float_out),
        .done(valid_out)
    );

endmodule