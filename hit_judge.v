`timescale 1ns/1ps
`include "baseball_defs.vh"

module hit_judge (
    input wire clk_sys,
    input wire rst,
    input wire [7:0] pitch_bus,
    input wire swing_pulse,
    input wire hbp_candidate,
    output reg result_valid,
    output reg [2:0] result_code
);
    wire active = pitch_bus[7];
    wire ending = pitch_bus[6];
    wire [1:0] pitch_type = pitch_bus[5:4];
    wire [3:0] position = pitch_bus[3:0];
    reg hbp_latched;
    reg judged;

    always @(posedge clk_sys) begin
        if (rst) begin
            hbp_latched <= 1'b0;
            judged <= 1'b0;
            result_valid <= 1'b0;
            result_code <= `RES_NONE;
        end else begin
            result_valid <= 1'b0;
            if (active && (position == 4'd0)) begin
                hbp_latched <= hbp_candidate;
                judged <= 1'b0;
            end else if (active && !judged && (swing_pulse || ending)) begin
                judged <= 1'b1;
                result_valid <= 1'b1;
                // Current pitch_bus is sampled before the LED advances.
                if (swing_pulse) begin
                    if (pitch_type == `PITCH_BALL)
                        result_code <= `RES_SWING_STRIKE;
                    else begin
                        case (position)
                            4'd6: result_code <= `RES_SINGLE;
                            4'd7: result_code <= `RES_DOUBLE;
                            4'd8: result_code <= `RES_HOMER;
                            default: result_code <= `RES_SWING_STRIKE;
                        endcase
                    end
                end else if (pitch_type == `PITCH_BALL) begin
                    result_code <= hbp_latched ? `RES_HBP : `RES_BALL;
                end else begin
                    result_code <= `RES_LOOKING_STRIKE;
                end
            end
        end
    end
endmodule
