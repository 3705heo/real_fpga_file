`timescale 1ns/1ps
`include "baseball_defs.vh"

module runner_update (
    input  wire [5:0] runner_req,
    output reg  [5:0] runner_res
);
    wire [2:0] occupied = runner_req[5:3];
    wire [2:0] advance = runner_req[2:0];

    always @* begin
        runner_res = {occupied, 3'd0};
        case (advance)
            `RUN_FORCE: begin
                // A runner moves only when forced by the batter and occupied
                // bases behind that runner.
                runner_res[5:3] = {
                    occupied[2] | (occupied[1] & occupied[0]),
                    occupied[1] | occupied[0],
                    1'b1
                };
                runner_res[2:0] = {2'b00, &occupied};
            end
            `RUN_SINGLE: begin
                runner_res[5:3] = {occupied[1:0], 1'b1};
                runner_res[2:0] = {2'b00, occupied[2]};
            end
            `RUN_DOUBLE: begin
                runner_res[5:3] = {occupied[0], 2'b10};
                runner_res[2:0] = {2'b00, occupied[2]} + {2'b00, occupied[1]};
            end
            `RUN_HOMER: begin
                runner_res[5:3] = 3'b000;
                runner_res[2:0] = 3'd1 + {2'b00, occupied[2]}
                                      + {2'b00, occupied[1]}
                                      + {2'b00, occupied[0]};
            end
            default: begin
                // No advance. Retain the default response.
            end
        endcase
    end
endmodule
