`timescale 1ns/1ps
`include "baseball_defs.vh"

module lcd_line_gen (
    input  wire [12:0]  lcd_state,
    output wire [127:0] line1,
    output reg  [127:0] line2
);
    wire done = lcd_state[12];
    wire [1:0] outcome = lcd_state[11:10];
    wire [2:0] recent = lcd_state[2:0];
    wire bottom = lcd_state[9];
    wire [7:0] balls = 8'h30 + {6'b0, lcd_state[8:7]};
    wire [7:0] strikes = 8'h30 + {6'b0, lcd_state[6:5]};
    wire [7:0] outs = 8'h30 + {6'b0, lcd_state[4:3]};

    // A line is exactly 16 bytes. The leftmost character occupies bits 127:120.
    assign line1 = {bottom ? "P2 BOT" : "P1 TOP", " B", balls,
                    " S", strikes, " O", outs, " "};

    always @* begin
        if (done) begin
            case (outcome)
                `OUTCOME_P1: line2 = "P1 WIN          ";
                `OUTCOME_P2: line2 = "P2 WIN          ";
                default: line2 = "DRAW            ";
            endcase
        end else begin
            case (recent)
                `RES_SWING_STRIKE: line2 = "SWING STRIKE    ";
                `RES_LOOKING_STRIKE: line2 = "LOOKING STRIKE  ";
                `RES_BALL: line2 = "BALL            ";
                `RES_HBP: line2 = "HBP             ";
                `RES_SINGLE: line2 = "SINGLE          ";
                `RES_DOUBLE: line2 = "DOUBLE          ";
                `RES_HOMER: line2 = "HOME RUN        ";
                default: line2 = "NO PITCH        ";
            endcase
        end
    end
endmodule
