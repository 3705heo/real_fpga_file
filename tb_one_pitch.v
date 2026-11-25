`timescale 1ns/1ps
`include "baseball_defs.vh"

module tb_one_pitch;
    localparam integer FAST_MS = 3;
    localparam integer EARLY_MS = 5;
    localparam integer LATE_MS = 1;

    reg clk_sys = 1'b0;
    reg rst = 1'b1;
    reg tick_ms = 1'b0;
    reg [3:0] pitch_ctrl = 4'b0;
    reg swing_pulse = 1'b0;
    reg hbp_candidate = 1'b0;
    wire [7:0] led;
    wire [7:0] pitch_bus;
    wire result_valid;
    wire [2:0] result_code;
    wire rng_candidate;
    wire zero_seed_candidate;

    integer outcomes;
    integer kind_index;
    integer position_index;
    integer lfsr_cycle;
    integer candidate_count;
    reg [1:0] kind;
    reg [2:0] expected_swing;

    always #5 clk_sys = ~clk_sys;

    pitch_engine #(
        .FAST_STEP_MS(FAST_MS), .CURVE_EARLY_MS(EARLY_MS), .CURVE_LATE_MS(LATE_MS)
    ) engine (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms),
        .pitch_ctrl(pitch_ctrl), .led(led), .pitch_bus(pitch_bus)
    );
    hit_judge judge (
        .clk_sys(clk_sys), .rst(rst), .pitch_bus(pitch_bus),
        .swing_pulse(swing_pulse), .hbp_candidate(hbp_candidate),
        .result_valid(result_valid), .result_code(result_code)
    );
    hbp_rng rng (
        .clk_sys(clk_sys), .rst(rst), .hbp_candidate(rng_candidate)
    );
    hbp_rng #(.HBP_SEED(16'h0000), .HBP_THRESHOLD(0)) rng_zero_seed (
        .clk_sys(clk_sys), .rst(rst), .hbp_candidate(zero_seed_candidate)
    );

    function [2:0] swing_result;
        input integer position;
        begin
            case (position)
                6: swing_result = `RES_SINGLE;
                7: swing_result = `RES_DOUBLE;
                8: swing_result = `RES_HOMER;
                default: swing_result = `RES_SWING_STRIKE;
            endcase
        end
    endfunction

    task check_result;
        input [2:0] expected;
        begin
            if ((result_valid !== (expected != `RES_NONE)) ||
                (result_valid && (result_code !== expected)))
                $fatal(1, "At %0t expected result %0d, got valid=%b code=%0d, bus=%b swing=%b tick=%b",
                       $time, expected, result_valid, result_code, pitch_bus, swing_pulse, tick_ms);
            if (result_valid)
                outcomes = outcomes + 1;
        end
    endtask

    task check_position;
        input integer position;
        reg [7:0] expected_led;
        begin
            expected_led = (position == 0) ? 8'b0 : (8'b1 << (position - 1));
            if ((led !== expected_led) ||
                (pitch_bus[7] !== (position != 0)) ||
                (pitch_bus[3:0] !== position[3:0]))
                $fatal(1, "At %0t expected pos=%0d LED=%b, got bus=%b LED=%b",
                       $time, position, expected_led, pitch_bus, led);
        end
    endtask

    task launch;
        input [1:0] pitch_kind;
        input candidate;
        input swing_during_start;
        input change_candidate_after_sample;
        begin
            outcomes = 0;
            @(negedge clk_sys);
            hbp_candidate = candidate;
            pitch_ctrl = {2'b10, pitch_kind};
            swing_pulse = swing_during_start;
            tick_ms = 1'b0;
            #1;
            if ((pitch_bus !== {2'b10, pitch_kind, 4'd0}) || (led !== 8'b0))
                $fatal(1, "Launch marker or pre-launch LED incorrect for pitch %b", pitch_kind);
            @(posedge clk_sys);
            // Change immediately after the launch sampling edge. A judge
            // sampling on the following edge would see the opposite value.
            if (change_candidate_after_sample)
                hbp_candidate <= !candidate;
            #1;
            check_position(1);
            check_result(`RES_NONE);
        end
    endtask

    task run_cycle;
        input enable_tick;
        input request_swing;
        input request_stop;
        input [2:0] expected;
        begin
            @(negedge clk_sys);
            pitch_ctrl = {1'b0, request_stop, 2'b00};
            tick_ms = enable_tick;
            swing_pulse = request_swing;
            @(posedge clk_sys);
            #1;
            check_result(expected);
        end
    endtask

    task reach;
        input [1:0] pitch_kind;
        input integer target;
        integer pos;
        integer dwell;
        integer t;
        begin
            for (pos = 1; pos < target; pos = pos + 1) begin
                dwell = FAST_MS;
                if (pitch_kind == `PITCH_CURVE)
                    dwell = (pos < 6) ? EARLY_MS : LATE_MS;
                for (t = 1; t <= dwell; t = t + 1) begin
                    run_cycle(1'b1, 1'b0, 1'b0, `RES_NONE);
                    check_position((t == dwell) ? (pos + 1) : pos);
                end
            end
        end
    endtask

    task close_without_swing;
        input [1:0] pitch_kind;
        input [2:0] expected;
        integer t;
        integer final_ticks;
        begin
            reach(pitch_kind, 8);
            final_ticks = (pitch_kind == `PITCH_CURVE) ? LATE_MS : FAST_MS;
            for (t = 1; t < final_ticks; t = t + 1)
                run_cycle(1'b1, 1'b0, 1'b0, `RES_NONE);
            run_cycle(1'b1, 1'b0, 1'b0, expected);
            check_position(0);
        end
    endtask

    task verify_single_outcome;
        begin
            // Exercise the immediately following edge as well as stop.
            run_cycle(1'b0, 1'b1, 1'b0, `RES_NONE);
            run_cycle(1'b1, 1'b1, 1'b1, `RES_NONE);
            check_position(0);
            run_cycle(1'b1, 1'b1, 1'b0, `RES_NONE);
            if (outcomes != 1)
                $fatal(1, "Expected exactly one result_valid pulse, saw %0d", outcomes);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk_sys);
        @(negedge clk_sys);
        rst = 1'b0;
        run_cycle(1'b0, 1'b1, 1'b0, `RES_NONE);

        for (kind_index = 0; kind_index < 2; kind_index = kind_index + 1) begin
            kind = (kind_index == 0) ? `PITCH_FAST : `PITCH_CURVE;
            for (position_index = 1; position_index <= 8; position_index = position_index + 1) begin
                launch(kind, 1'b1, 1'b1, 1'b0);
                reach(kind, position_index);
                expected_swing = swing_result(position_index);
                run_cycle(1'b0, 1'b1, 1'b0, expected_swing);
                verify_single_outcome;
            end
            launch(kind, 1'b1, 1'b0, 1'b0);
            close_without_swing(kind, `RES_LOOKING_STRIKE);
            verify_single_outcome;
        end

        launch(`PITCH_BALL, 1'b0, 1'b0, 1'b1);
        close_without_swing(`PITCH_BALL, `RES_BALL);
        verify_single_outcome;
        launch(`PITCH_BALL, 1'b1, 1'b0, 1'b1);
        close_without_swing(`PITCH_BALL, `RES_HBP);
        verify_single_outcome;
        launch(`PITCH_BALL, 1'b1, 1'b0, 1'b1);
        reach(`PITCH_BALL, 8);
        run_cycle(1'b1, 1'b0, 1'b0, `RES_NONE);
        run_cycle(1'b1, 1'b0, 1'b0, `RES_NONE);
        run_cycle(1'b1, 1'b1, 1'b0, `RES_SWING_STRIKE);
        check_position(0);
        verify_single_outcome;

        // LED 7 -> 8: one tick before, at the step, and next system edge.
        launch(`PITCH_FAST, 1'b0, 1'b0, 1'b0);
        reach(`PITCH_FAST, 7);
        run_cycle(1'b1, 1'b0, 1'b0, `RES_NONE);
        run_cycle(1'b1, 1'b1, 1'b0, `RES_DOUBLE);
        check_position(7);
        verify_single_outcome;

        launch(`PITCH_FAST, 1'b0, 1'b0, 1'b0);
        reach(`PITCH_FAST, 7);
        run_cycle(1'b1, 1'b0, 1'b0, `RES_NONE);
        run_cycle(1'b1, 1'b0, 1'b0, `RES_NONE);
        run_cycle(1'b1, 1'b1, 1'b0, `RES_DOUBLE);
        check_position(8);
        verify_single_outcome;

        launch(`PITCH_FAST, 1'b0, 1'b0, 1'b0);
        reach(`PITCH_FAST, 8);
        run_cycle(1'b0, 1'b1, 1'b0, `RES_HOMER);
        verify_single_outcome;

        // LED 8 -> idle: before, at the terminal edge, and immediately after.
        launch(`PITCH_FAST, 1'b0, 1'b0, 1'b0);
        reach(`PITCH_FAST, 8);
        run_cycle(1'b1, 1'b0, 1'b0, `RES_NONE);
        run_cycle(1'b1, 1'b1, 1'b0, `RES_HOMER);
        check_position(8);
        verify_single_outcome;

        launch(`PITCH_FAST, 1'b0, 1'b0, 1'b0);
        reach(`PITCH_FAST, 8);
        run_cycle(1'b1, 1'b0, 1'b0, `RES_NONE);
        run_cycle(1'b1, 1'b0, 1'b0, `RES_NONE);
        run_cycle(1'b1, 1'b1, 1'b0, `RES_HOMER);
        check_position(0);
        verify_single_outcome;

        launch(`PITCH_FAST, 1'b0, 1'b0, 1'b0);
        close_without_swing(`PITCH_FAST, `RES_LOOKING_STRIKE);
        verify_single_outcome;

        // Reset has priority even when a swing is presented at LED 6.
        launch(`PITCH_FAST, 1'b0, 1'b0, 1'b0);
        reach(`PITCH_FAST, 6);
        @(negedge clk_sys);
        rst = 1'b1;
        swing_pulse = 1'b1;
        @(posedge clk_sys);
        #1;
        check_result(`RES_NONE);
        check_position(0);
        if ((result_code !== `RES_NONE) || (rng.state !== 16'h1ACE) ||
            (rng_zero_seed.state !== 16'h0001))
            $fatal(1, "Reset failed to clear judge or seed rng");

        @(negedge clk_sys);
        rst = 1'b0;
        candidate_count = 0;
        for (lfsr_cycle = 1; lfsr_cycle <= 65_535; lfsr_cycle = lfsr_cycle + 1) begin
            @(posedge clk_sys);
            #1;
            if ((rng.state == 0) || (rng_zero_seed.state == 0) || zero_seed_candidate)
                $fatal(1, "Invalid LFSR state or threshold-zero result on cycle %0d", lfsr_cycle);
            if (rng_candidate)
                candidate_count = candidate_count + 1;
            if ((rng.state == 16'h1ACE) && (lfsr_cycle != 65_535))
                $fatal(1, "LFSR repeated early on cycle %0d", lfsr_cycle);
        end
        if ((rng.state !== 16'h1ACE) || (candidate_count != 9830))
            $fatal(1, "Expected seed recurrence and 9830/65535 candidates, got state %h and %0d hits",
                   rng.state, candidate_count);

        $display("PASS tb_one_pitch");
        $finish;
    end

    initial begin
        #1_000_000;
        $fatal(1, "Timeout in tb_one_pitch");
    end
endmodule
