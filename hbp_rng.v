`timescale 1ns/1ps

module hbp_rng #(
    parameter [15:0] HBP_SEED = 16'h1ACE,
    parameter integer HBP_THRESHOLD = 9830
) (
    input wire clk_sys,
    input wire rst,
    output wire hbp_candidate
);
    localparam [15:0] INITIAL_STATE =
        (HBP_SEED == 16'h0000) ? 16'h0001 : HBP_SEED;
    reg [15:0] state;
    wire feedback = state[15] ^ state[13] ^ state[12] ^ state[10];

    // A maximal-length LFSR visits all 65,535 nonzero states. The inclusive
    // comparison yields exactly HBP_THRESHOLD asserted states per period
    // when the threshold is in the documented range 0 to 65,535.
    assign hbp_candidate = (state != 16'h0000) &&
                           ({16'b0, state} <= HBP_THRESHOLD);

    always @(posedge clk_sys) begin
        if (rst || (state == 16'h0000))
            state <= INITIAL_STATE;
        else
            state <= {state[14:0], feedback};
    end
endmodule
