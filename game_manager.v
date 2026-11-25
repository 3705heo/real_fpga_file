`timescale 1ns/1ps
`include "baseball_defs.vh"

module game_manager #(
    parameter integer PREP_MS   = 300,
    parameter integer RESULT_MS = 950
) (
    input  wire        clk_sys,
    input  wire        rst,
    input  wire        tick_ms,
    input  wire        pitch_req,
    input  wire [1:0]  pitch_sel,
    input  wire        result_valid,
    input  wire [2:0]  result_code,
    input  wire [5:0]  runner_res,
    output wire [3:0]  pitch_ctrl,
    output wire [5:0]  runner_req,
    output wire [15:0] scores,
    output reg  [2:0]  bases,
    output wire [12:0] lcd_state,
    output wire [1:0]  fx_evt
);
    localparam [2:0] WAIT_PITCH     = 3'd0,
                     PREPARE        = 3'd1,
                     PITCHING       = 3'd2,
                     APPLY_RESULT   = 3'd3,
                     DISPLAY_RESULT = 3'd4,
                     GAME_OVER      = 3'd5;

    function integer counter_width;
        input integer duration;
        integer remaining;
        begin
            counter_width = 1;
            for (remaining = duration - 1; remaining > 1; remaining = remaining >> 1)
                counter_width = counter_width + 1;
        end
    endfunction

    localparam integer TIMER_WIDTH =
        counter_width((PREP_MS > RESULT_MS) ? PREP_MS : RESULT_MS);

    reg [2:0] state;
    reg [TIMER_WIDTH-1:0] elapsed_ms;
    reg [1:0] selected_pitch;
    reg [2:0] pending_result;
    reg [2:0] recent_result;
    reg [1:0] balls;
    reg [1:0] strikes;
    reg [1:0] outs;
    reg       bottom;
    reg [1:0] outcome;
    reg [7:0] score_p1;
    reg [7:0] score_p2;
    reg [2:0] advance;

    localparam [TIMER_WIDTH-1:0] PREP_LAST_TICK = PREP_MS - 1;
    localparam [TIMER_WIDTH-1:0] SHOW_LAST_TICK = RESULT_MS - 1;

    wire accept_pitch = !rst && (state == WAIT_PITCH) && pitch_req &&
                        (pitch_sel != 2'b11);
    wire start_pitch = !rst && (state == PREPARE) && tick_ms &&
                       (elapsed_ms == PREP_LAST_TICK);
    wire stop_pitch = !rst && (state == PITCHING) && result_valid;
    wire homer_scored = !rst && (state == APPLY_RESULT) &&
                       (pending_result == `RES_HOMER);

    // The added bit preserves any carry beyond the displayed 8-bit score.
    wire [8:0] score_sum = {1'b0, (bottom ? score_p2 : score_p1)}
                         + {6'b000000, runner_res[2:0]};
    wire [7:0] updated_score = score_sum[8] ? 8'hff : score_sum[7:0];

    assign pitch_ctrl = {start_pitch, stop_pitch, selected_pitch};
    assign runner_req = {bases, advance};
    assign scores = {score_p1, score_p2};
    assign lcd_state = {state == GAME_OVER, outcome, bottom, balls,
                        strikes, outs, recent_result};
    // Both effects are consumed at the edge that accepts or applies the event.
    assign fx_evt = accept_pitch ? `FX_PREP :
                    homer_scored ? `FX_HOMER : `FX_NONE;

    // A received result is registered before requesting any runner updates.
    // APPLY_RESULT consumes the combinational response at the following edge.
    always @* begin
        advance = `RUN_NONE;
        if (state == APPLY_RESULT) begin
            case (pending_result)
                `RES_BALL: if (balls == 2'd3) advance = `RUN_FORCE;
                `RES_HBP:   advance = `RUN_FORCE;
                `RES_SINGLE: advance = `RUN_SINGLE;
                `RES_DOUBLE: advance = `RUN_DOUBLE;
                `RES_HOMER:  advance = `RUN_HOMER;
                default: begin
                    // The result leaves any occupied bases in place.
                end
            endcase
        end
    end

    always @(posedge clk_sys) begin
        if (rst) begin
            state          <= WAIT_PITCH;
            elapsed_ms     <= {TIMER_WIDTH{1'b0}};
            selected_pitch <= `PITCH_FAST;
            pending_result <= `RES_NONE;
            recent_result  <= `RES_NONE;
            balls          <= 2'd0;
            strikes        <= 2'd0;
            outs           <= 2'd0;
            bottom         <= 1'b0;
            outcome        <= `OUTCOME_PLAY;
            score_p1       <= 8'd0;
            score_p2       <= 8'd0;
            bases          <= 3'b000;
        end else begin
            case (state)
                WAIT_PITCH: begin
                    if (accept_pitch) begin
                        selected_pitch <= pitch_sel;
                        elapsed_ms <= {TIMER_WIDTH{1'b0}};
                        state <= PREPARE;
                    end
                end
                PREPARE: begin
                    if (start_pitch) begin
                        state <= PITCHING;
                    end else if (tick_ms) begin
                        elapsed_ms <= elapsed_ms + 1'b1;
                    end
                end
                PITCHING: begin
                    if (result_valid) begin
                        pending_result <= result_code;
                        state <= APPLY_RESULT;
                    end
                end
                APPLY_RESULT: begin
                    recent_result <= pending_result;
                    elapsed_ms <= {TIMER_WIDTH{1'b0}};
                    state <= DISPLAY_RESULT;
                    if (advance != `RUN_NONE) begin
                        bases <= runner_res[5:3];
                        balls <= 2'd0;
                        strikes <= 2'd0;
                        if (bottom)
                            score_p2 <= updated_score;
                        else
                            score_p1 <= updated_score;
                    end else begin
                        case (pending_result)
                            `RES_BALL: balls <= balls + 1'b1;
                            `RES_SWING_STRIKE, `RES_LOOKING_STRIKE: begin
                                if (strikes < 2'd2) begin
                                    strikes <= strikes + 1'b1;
                                end else begin
                                    balls <= 2'd0;
                                    strikes <= 2'd0;
                                    if (outs < 2'd2) begin
                                        outs <= outs + 1'b1;
                                    end else begin
                                        bases <= 3'b000;
                                        if (!bottom) begin
                                            outs <= 2'd0;
                                            bottom <= 1'b1;
                                        end else begin
                                            outs <= 2'd3;
                                            state <= GAME_OVER;
                                            if (score_p1 > score_p2)
                                                outcome <= `OUTCOME_P1;
                                            else if (score_p2 > score_p1)
                                                outcome <= `OUTCOME_P2;
                                            else
                                                outcome <= `OUTCOME_DRAW;
                                        end
                                    end
                                end
                            end
                            default: begin
                                // The result requires no count change.
                            end
                        endcase
                    end
                end
                DISPLAY_RESULT: begin
                    if (tick_ms) begin
                        if (elapsed_ms == SHOW_LAST_TICK)
                            state <= WAIT_PITCH;
                        else
                            elapsed_ms <= elapsed_ms + 1'b1;
                    end
                end
                GAME_OVER: begin
                    // Hold the final display until a reset.
                end
                default: state <= WAIT_PITCH;
            endcase
        end
    end
endmodule
