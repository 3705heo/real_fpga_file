`timescale 1ns/1ps
`include "baseball_defs.vh"

module tb_game_manager;
    localparam integer PREP_TICKS = 3;
    localparam integer SHOW_TICKS = 3;

    reg clk_sys = 1'b0;
    reg rst = 1'b1;
    reg tick_ms = 1'b1;
    reg pitch_req = 1'b0;
    reg [1:0] pitch_sel = `PITCH_FAST;
    reg result_valid = 1'b0;
    reg [2:0] result_code = `RES_NONE;

    wire [5:0] runner_res;
    wire [3:0] pitch_ctrl;
    wire [5:0] runner_req;
    wire [15:0] scores;
    wire [2:0] bases;
    wire [12:0] lcd_state;
    wire [1:0] fx_evt;

    integer prep_edges = 0;
    integer launch_edges = 0;
    integer stop_edges = 0;
    integer homer_edges = 0;
    reg [1:0] launched_selection;
    integer loop_index;

    game_manager #(.PREP_MS(PREP_TICKS), .RESULT_MS(SHOW_TICKS)) dut (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms),
        .pitch_req(pitch_req), .pitch_sel(pitch_sel),
        .result_valid(result_valid), .result_code(result_code),
        .runner_res(runner_res), .pitch_ctrl(pitch_ctrl),
        .runner_req(runner_req), .scores(scores), .bases(bases),
        .lcd_state(lcd_state), .fx_evt(fx_evt)
    );
    runner_update runner (.runner_req(runner_req), .runner_res(runner_res));

    always #5 clk_sys = ~clk_sys;

    always @(posedge clk_sys) begin
        if (!rst) begin
            if (fx_evt == `FX_PREP)
                prep_edges = prep_edges + 1;
            if (fx_evt == `FX_HOMER)
                homer_edges = homer_edges + 1;
            if (pitch_ctrl[3]) begin
                launch_edges = launch_edges + 1;
                launched_selection = pitch_ctrl[1:0];
            end
            if (pitch_ctrl[2])
                stop_edges = stop_edges + 1;
        end
    end

    task expect_state;
        input [8*64-1:0] message;
        input [7:0] p1;
        input [7:0] p2;
        input [2:0] occupied;
        input [1:0] expected_outcome;
        input expected_bottom;
        input [1:0] expected_balls;
        input [1:0] expected_strikes;
        input [1:0] expected_outs;
        input [2:0] expected_recent;
        reg [12:0] expected_lcd;
        begin
            expected_lcd = {expected_outcome != `OUTCOME_PLAY, expected_outcome,
                            expected_bottom, expected_balls, expected_strikes,
                            expected_outs, expected_recent};
            if (scores !== {p1, p2} || bases !== occupied || lcd_state !== expected_lcd)
                $fatal(1, "%0s: expected scores %0d:%0d bases %b lcd %b, got %0d:%0d bases %b lcd %b",
                       message, p1, p2, occupied, expected_lcd,
                       scores[15:8], scores[7:0], bases, lcd_state);
        end
    endtask

    task reset_game;
        begin
            @(negedge clk_sys);
            rst = 1'b1;
            // Reset must win even if both request signals are present.
            pitch_req = 1'b1;
            result_valid = 1'b1;
            result_code = `RES_HOMER;
            @(posedge clk_sys);
            #1;
            expect_state("reset", 0, 0, 0, `OUTCOME_PLAY, 0, 0, 0, 0, `RES_NONE);
            if (pitch_ctrl[3:2] !== 2'b00 || fx_evt !== `FX_NONE)
                $fatal(1, "reset left pitch control or an effect active");
            @(negedge clk_sys);
            pitch_req = 1'b0;
            result_valid = 1'b0;
            rst = 1'b0;
        end
    endtask

    task start_pitch;
        input [1:0] selection;
        input try_reselect;
        integer prev_prep;
        integer prev_launch;
        integer tick;
        begin
            prev_prep = prep_edges;
            prev_launch = launch_edges;
            @(negedge clk_sys);
            pitch_req = 1'b1;
            pitch_sel = selection;
            @(posedge clk_sys);
            #1;
            if (prep_edges != prev_prep + 1 || launch_edges != prev_launch)
                $fatal(1, "pitch request did not start preparation alone");
            @(negedge clk_sys);
            pitch_req = try_reselect;
            pitch_sel = `PITCH_BALL;
            for (tick = 1; tick < PREP_TICKS; tick = tick + 1) begin
                @(posedge clk_sys);
                #1;
                if (prep_edges != prev_prep + 1 || launch_edges != prev_launch)
                    $fatal(1, "early pitch start or repeated preparation on elapsed tick %0d", tick);
                @(negedge clk_sys);
                pitch_req = 1'b0;
            end
            @(posedge clk_sys);
            #1;
            if (launch_edges != prev_launch + 1 || launched_selection !== selection)
                $fatal(1, "expected pitch selection %0d, launched selection %0d in %0d starts",
                       selection, launched_selection, launch_edges - prev_launch);
        end
    endtask

    task receive_result;
        input [2:0] code;
        input try_extra_inputs;
        reg [15:0] prior_scores;
        reg [2:0] prior_bases;
        reg [12:0] prior_lcd;
        integer prev_stop;
        integer prev_homer;
        begin
            prior_scores = scores;
            prior_bases = bases;
            prior_lcd = lcd_state;
            prev_stop = stop_edges;
            prev_homer = homer_edges;
            @(negedge clk_sys);
            result_valid = 1'b1;
            result_code = code;
            pitch_req = try_extra_inputs;
            @(posedge clk_sys);
            #1;
            if (stop_edges != prev_stop + 1)
                $fatal(1, "result %0d did not stop the pitch once", code);
            if (scores !== prior_scores || bases !== prior_bases || lcd_state !== prior_lcd)
                $fatal(1, "result %0d changed game state before the runner commit edge", code);

            @(negedge clk_sys);
            result_valid = try_extra_inputs;
            // A later code must not replace the already latched result.
            result_code = `RES_DOUBLE;
            pitch_req = 1'b0;
            @(posedge clk_sys);
            #1;
            if (lcd_state[2:0] !== code)
                $fatal(1, "latched result %0d was applied as %0d", code, lcd_state[2:0]);
            if (code == `RES_HOMER) begin
                if (homer_edges != prev_homer + 1)
                    $fatal(1, "home run did not emit one effect with the commit");
            end else if (homer_edges != prev_homer)
                $fatal(1, "non-home-run result %0d emitted a home run effect", code);
        end
    endtask

    task finish_display;
        input try_extra_inputs;
        reg [15:0] held_scores;
        reg [2:0] held_bases;
        reg [12:0] held_lcd;
        integer prev_prep;
        integer prev_launch;
        integer prev_stop;
        integer prev_homer;
        begin
            held_scores = scores;
            held_bases = bases;
            held_lcd = lcd_state;
            prev_prep = prep_edges;
            prev_launch = launch_edges;
            prev_stop = stop_edges;
            prev_homer = homer_edges;
            @(negedge clk_sys);
            pitch_req = try_extra_inputs;
            result_valid = try_extra_inputs;
            repeat (SHOW_TICKS) begin
                @(posedge clk_sys);
                #1;
                if (scores !== held_scores || bases !== held_bases || lcd_state !== held_lcd)
                    $fatal(1, "another game update occurred during the result display");
                if (prep_edges != prev_prep || launch_edges != prev_launch ||
                    stop_edges != prev_stop || homer_edges != prev_homer)
                    $fatal(1, "extra request or result was consumed during the result display");
                @(negedge clk_sys);
                pitch_req = 1'b0;
                result_valid = 1'b0;
            end
        end
    endtask

    task play_result;
        input [2:0] code;
        begin
            start_pitch(`PITCH_FAST, 1'b0);
            receive_result(code, 1'b0);
            finish_display(1'b0);
        end
    endtask

    task strikeout;
        begin
            play_result(`RES_SWING_STRIKE);
            play_result(`RES_LOOKING_STRIKE);
            play_result(`RES_LOOKING_STRIKE);
        end
    endtask

    task advance_half;
        begin
            strikeout;
            strikeout;
            strikeout;
        end
    endtask

    task check_end_lock;
        reg [15:0] held_scores;
        reg [2:0] held_bases;
        reg [12:0] held_lcd;
        integer prev_prep;
        integer prev_launch;
        integer prev_stop;
        begin
            held_scores = scores;
            held_bases = bases;
            held_lcd = lcd_state;
            prev_prep = prep_edges;
            prev_launch = launch_edges;
            prev_stop = stop_edges;
            @(negedge clk_sys);
            pitch_req = 1'b1;
            result_valid = 1'b1;
            result_code = `RES_HOMER;
            repeat (PREP_TICKS + SHOW_TICKS + 2) @(posedge clk_sys);
            #1;
            if (scores !== held_scores || bases !== held_bases || lcd_state !== held_lcd ||
                prep_edges != prev_prep || launch_edges != prev_launch || stop_edges != prev_stop)
                $fatal(1, "game accepted input after the final out");
            @(negedge clk_sys);
            pitch_req = 1'b0;
            result_valid = 1'b0;
        end
    endtask

    initial begin
        reset_game;
        play_result(`RES_BALL);
        expect_state("first ball", 0, 0, 0, `OUTCOME_PLAY, 0, 1, 0, 0, `RES_BALL);
        play_result(`RES_BALL);
        expect_state("second ball", 0, 0, 0, `OUTCOME_PLAY, 0, 2, 0, 0, `RES_BALL);
        play_result(`RES_BALL);
        expect_state("third ball", 0, 0, 0, `OUTCOME_PLAY, 0, 3, 0, 0, `RES_BALL);
        play_result(`RES_SWING_STRIKE);
        expect_state("strike before walk", 0, 0, 0, `OUTCOME_PLAY, 0, 3, 1, 0, `RES_SWING_STRIKE);
        play_result(`RES_BALL);
        expect_state("fourth ball walks", 0, 0, 1, `OUTCOME_PLAY, 0, 0, 0, 0, `RES_BALL);
        play_result(`RES_BALL);
        play_result(`RES_LOOKING_STRIKE);
        play_result(`RES_HBP);
        expect_state("HBP immediately forces runner and resets count",
                     0, 0, 3, `OUTCOME_PLAY, 0, 0, 0, 0, `RES_HBP);
        play_result(`RES_SINGLE);
        expect_state("single loads bases", 0, 0, 7, `OUTCOME_PLAY, 0, 0, 0, 0, `RES_SINGLE);

        start_pitch(`PITCH_CURVE, 1'b1);
        receive_result(`RES_HOMER, 1'b1);
        expect_state("four runs at exactly one commit", 4, 0, 0, `OUTCOME_PLAY, 0, 0, 0, 0, `RES_HOMER);
        finish_display(1'b1);

        play_result(`RES_BALL);
        play_result(`RES_SWING_STRIKE);
        play_result(`RES_LOOKING_STRIKE);
        expect_state("second strike retains count", 4, 0, 0, `OUTCOME_PLAY, 0, 1, 2, 0, `RES_LOOKING_STRIKE);
        play_result(`RES_SWING_STRIKE);
        expect_state("third strike is one out", 4, 0, 0, `OUTCOME_PLAY, 0, 0, 0, 1, `RES_SWING_STRIKE);
        play_result(`RES_DOUBLE);
        strikeout;
        expect_state("second out holds runner", 4, 0, 2, `OUTCOME_PLAY, 0, 0, 0, 2, `RES_LOOKING_STRIKE);
        play_result(`RES_BALL);
        strikeout;
        expect_state("top third out changes sides and clears bases and counts",
                     4, 0, 0, `OUTCOME_PLAY, 1, 0, 0, 0, `RES_LOOKING_STRIKE);
        play_result(`RES_HOMER);
        expect_state("only current batting side gains a run",
                     4, 1, 0, `OUTCOME_PLAY, 1, 0, 0, 0, `RES_HOMER);
        play_result(`RES_SINGLE);
        advance_half;
        expect_state("P1 win after bottom third out", 4, 1, 0, `OUTCOME_P1, 1, 0, 0, 3, `RES_LOOKING_STRIKE);
        check_end_lock;

        reset_game;
        play_result(`RES_HOMER);
        advance_half;
        play_result(`RES_HOMER);
        play_result(`RES_HOMER);
        expect_state("P2 lead does not end game", 1, 2, 0, `OUTCOME_PLAY, 1, 0, 0, 0, `RES_HOMER);
        play_result(`RES_HBP);
        expect_state("P2 takes another plate appearance after lead",
                     1, 2, 1, `OUTCOME_PLAY, 1, 0, 0, 0, `RES_HBP);
        advance_half;
        expect_state("P2 win after bottom third out", 1, 2, 0, `OUTCOME_P2, 1, 0, 0, 3, `RES_LOOKING_STRIKE);

        reset_game;
        advance_half;
        advance_half;
        expect_state("draw after bottom third out", 0, 0, 0, `OUTCOME_DRAW, 1, 0, 0, 3, `RES_LOOKING_STRIKE);

        reset_game;
        // Reach 254 through game transactions, then make a four-run homer.
        for (loop_index = 0; loop_index < 63; loop_index = loop_index + 1) begin
            play_result(`RES_SINGLE);
            play_result(`RES_SINGLE);
            play_result(`RES_SINGLE);
            play_result(`RES_HOMER);
        end
        play_result(`RES_HOMER);
        play_result(`RES_HOMER);
        expect_state("score before carry", 254, 0, 0, `OUTCOME_PLAY, 0, 0, 0, 0, `RES_HOMER);
        play_result(`RES_SINGLE);
        play_result(`RES_SINGLE);
        play_result(`RES_SINGLE);
        play_result(`RES_HOMER);
        expect_state("254 plus four saturates", 255, 0, 0, `OUTCOME_PLAY, 0, 0, 0, 0, `RES_HOMER);
        play_result(`RES_HOMER);
        expect_state("255 stays saturated", 255, 0, 0, `OUTCOME_PLAY, 0, 0, 0, 0, `RES_HOMER);

        // Interrupt the pipeline after the result has been latched.
        start_pitch(`PITCH_FAST, 1'b0);
        @(negedge clk_sys);
        result_valid = 1'b1;
        result_code = `RES_HOMER;
        @(posedge clk_sys);
        #1;
        if (runner_req[2:0] !== `RUN_HOMER)
            $fatal(1, "mid-game reset setup did not reach pending commit");
        reset_game;
        play_result(`RES_SINGLE);
        expect_state("play resumes at P1 after reset", 0, 0, 1, `OUTCOME_PLAY, 0, 0, 0, 0, `RES_SINGLE);

        $display("PASS tb_game_manager");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "tb_game_manager timed out");
    end
endmodule
