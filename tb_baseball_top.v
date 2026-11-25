`timescale 1ns/1ps
`include "baseball_defs.vh"

module tb_baseball_top;
    localparam integer CLK_HZ = 10000;
    localparam integer CLOCKS_MS = CLK_HZ / 1000;
    localparam integer RESULT_MS = 10;
    localparam integer FAST_STEP_MS = 7;
    localparam integer CURVE_EARLY_MS = 10;
    localparam integer CURVE_LATE_MS = 4;

    reg clk_sys = 1'b0;
    always #50000 clk_sys = ~clk_sys;
    reg sw_0 = 1'b0;
    reg sw_1 = 1'b0;
    reg sw_2 = 1'b0;
    reg sw_3 = 1'b0;
    reg sw_star = 1'b0;
    wire [7:0] led, seg_com, seg_data, lcd_data;
    wire [2:0] base_lights;
    wire [3:0] rgb_r, rgb_g, rgb_b;
    wire piezo, lcd_rs, lcd_rw, lcd_e;

    baseball_top #(
        .CLK_HZ(CLK_HZ), .DEBOUNCE_MS(2), .PREP_MS(6),
        .FAST_STEP_MS(FAST_STEP_MS), .CURVE_EARLY_MS(CURVE_EARLY_MS),
        .CURVE_LATE_MS(CURVE_LATE_MS),
        .RESULT_MS(RESULT_MS), .HOMER_MS(8)
    ) dut (
        .clk_sys(clk_sys), .sw_0(sw_0), .sw_1(sw_1), .sw_2(sw_2),
        .sw_3(sw_3), .sw_star(sw_star),
        .led(led), .seg_com(seg_com), .seg_data(seg_data), .base_lights(base_lights),
        .piezo(piezo), .rgb_r(rgb_r), .rgb_g(rgb_g), .rgb_b(rgb_b),
        .lcd_data(lcd_data), .lcd_rs(lcd_rs), .lcd_rw(lcd_rw), .lcd_e(lcd_e)
    );

    integer launched = 0;
    integer judged = 0;
    integer prepare_edges = 0;
    reg [2:0] last_code = `RES_NONE;
    reg homer_light_seen = 0;
    always @(posedge clk_sys) begin
        if (!dut.rst) begin
            if (dut.pitch_ctrl[3]) launched <= launched + 1;
            if (dut.fx_evt == `FX_PREP) prepare_edges <= prepare_edges + 1;
            if (dut.result_valid) begin
                judged <= judged + 1;
                last_code <= dut.result_code;
            end
            if (rgb_r != 0 && rgb_g != 0 && rgb_b == 0) homer_light_seen <= 1;
        end
    end

    task clocks;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) @(negedge clk_sys);
        end
    endtask

    task require_state;
        input [15:0] expected_scores;
        input [2:0] expected_bases;
        input [2:0] expected_status; // {done, outcome}
        input expected_bottom;
        input [1:0] expected_outs;
        begin
            if (dut.scores !== expected_scores || base_lights !== expected_bases ||
                dut.lcd_state[12:10] !== expected_status || dut.lcd_state[9] !== expected_bottom ||
                dut.lcd_state[4:3] !== expected_outs)
                $fatal(1, "game state: expected score=%h bases=%b status=%b bottom=%b outs=%d; got %h %b %b %b %d",
                    expected_scores, expected_bases, expected_status, expected_bottom, expected_outs,
                    dut.scores, base_lights, dut.lcd_state[12:10], dut.lcd_state[9], dut.lcd_state[4:3]);
        end
    endtask

    task reset_button;
        begin
            sw_star = 1;
            clocks(4 * CLOCKS_MS);
            if (dut.rst !== 1 || led !== 0 || piezo !== 0 || {rgb_r, rgb_g, rgb_b} !== 0)
                $fatal(1, "SW_* reset did not clear the ball and effects");
            require_state(16'h0000, 3'b000, 3'b000, 1'b0, 2'd0);
            if (dut.lcd_state[8:5] !== 0 || dut.lcd_state[2:0] !== `RES_NONE)
                $fatal(1, "SW_* reset did not clear counts and recent result");
            sw_star = 0;
            clocks(4 * CLOCKS_MS);
            if (dut.rst !== 0) $fatal(1, "SW_* reset did not release");
        end
    endtask

    task play_fastball;
        input integer swing_led;
        input [2:0] expected;
        input exercise_ignored_buttons;
        integer old_launched, old_judged, old_prepares;
        reg prep_sound_seen;
        reg [7:0] target_led;
        begin
            old_launched = launched;
            old_judged = judged;
            old_prepares = prepare_edges;
            prep_sound_seen = 0;
            sw_1 = 1;
            if (exercise_ignored_buttons) sw_0 = 1;
            clocks(3 * CLOCKS_MS);
            sw_1 = 0;
            while (led == 0) begin
                if (piezo == 1) prep_sound_seen = 1;
                if (judged != old_judged) $fatal(1, "Judge accepted a swing during preparation");
                clocks(1);
            end
            if (!prep_sound_seen || led !== 8'h01 || piezo !== 0)
                $fatal(1, "Expected prepare tone before LED1 and silence on LED1");
            if (exercise_ignored_buttons) begin
                sw_2 = 1;
                clocks(4 * CLOCKS_MS);
                if (led !== 8'h01 || judged != old_judged)
                    $fatal(1, "Held preparation swing carried into LED1");
                sw_0 = 0;
                sw_2 = 0;
            end
            if (swing_led != 0) begin
                target_led = 8'b1 << (swing_led - 1);
                while (led !== target_led) clocks(1);
                sw_0 = 1;
                clocks(4 * CLOCKS_MS);
                sw_0 = 0;
            end
            while (judged == old_judged) clocks(1);
            if (last_code !== expected)
                $fatal(1, "SW_0 target LED %0d: expected code %0d, got %0d", swing_led, expected, last_code);
            clocks(2);
            if (led !== 8'h00) $fatal(1, "LEDs did not clear after result %d", expected);
            if (exercise_ignored_buttons) begin
                sw_3 = 1;
                clocks(4 * CLOCKS_MS);
                sw_3 = 0;
            end
            clocks((RESULT_MS + 5) * CLOCKS_MS);
            if (judged != old_judged + 1 || launched != old_launched + 1 ||
                prepare_edges != old_prepares + 1 || led !== 8'h00)
                $fatal(1, "Expected one pitch, preparation, and judgement for LED %0d", swing_led);
        end
    endtask

    task three_outs;
        integer pitch_index;
        begin
            for (pitch_index = 0; pitch_index < 9; pitch_index = pitch_index + 1)
                play_fastball(0, `RES_LOOKING_STRIKE, 1'b0);
        end
    endtask

    integer end_launched, end_judged;
    integer scanned_digits;
    initial begin
        clocks(8 * CLOCKS_MS);
        reset_button;
        play_fastball(6, `RES_SINGLE, 1'b1);
        require_state(16'h0000, 3'b001, 3'b000, 1'b0, 2'd0);
        play_fastball(7, `RES_DOUBLE, 1'b0);
        require_state(16'h0000, 3'b110, 3'b000, 1'b0, 2'd0);
        play_fastball(8, `RES_HOMER, 1'b0);
        require_state(16'h0300, 3'b000, 3'b000, 1'b0, 2'd0);
        if (!homer_light_seen) $fatal(1, "Homer did not light the RGB effect");
        scanned_digits = 0;
        repeat (9 * CLOCKS_MS) begin
            clocks(1);
            if (seg_com != 0) begin
                scanned_digits = scanned_digits | seg_com;
                if (seg_data !== ((seg_com == 8'h08) ? 8'h4f : 8'h3f))
                    $fatal(1, "Expected score display 00030000, got com=%h seg=%h", seg_com, seg_data);
            end
        end
        if (scanned_digits != 255) $fatal(1, "Did not scan all score digits");

        three_outs;
        require_state(16'h0300, 3'b000, 3'b000, 1'b1, 2'd0);
        three_outs;
        require_state(16'h0300, 3'b000, 3'b101, 1'b1, 2'd3);
        if (dut.line2 !== "P1 WIN          ") $fatal(1, "Expected P1 WIN on LCD");
        end_launched = launched;
        end_judged = judged;
        sw_3 = 1;
        sw_0 = 1;
        clocks(8 * CLOCKS_MS);
        sw_3 = 0;
        sw_0 = 0;
        clocks(8 * CLOCKS_MS);
        if (led !== 0 || launched != end_launched || judged != end_judged)
            $fatal(1, "Game accepted buttons after the final out");
        require_state(16'h0300, 3'b000, 3'b101, 1'b1, 2'd3);

        reset_button;
        // A real, debounced SW_* press interrupts the moving ball as well.
        sw_2 = 1;
        clocks(4 * CLOCKS_MS);
        sw_2 = 0;
        // Press too late in preparation to debounce until LED 1 is visible.
        while (!dut.pitch_ctrl[3]) clocks(1);
        sw_0 = 1;
        end_judged = judged;
        clocks(1);
        if (led !== 8'h01)
            $fatal(1, "Curve did not start on LED1");
        clocks(4 * CLOCKS_MS);
        if (led !== 8'h01 || judged != end_judged)
            $fatal(1, "Late preparation press leaked through the debounce into LED1");
        sw_0 = 0;
        // Check that the top-level curve override reaches the physical LED path.
        clocks((CURVE_EARLY_MS - 4) * CLOCKS_MS - 1);
        if (led !== 8'h01)
            $fatal(1, "Curve left LED1 before CURVE_EARLY_MS elapsed");
        clocks(1);
        if (led !== 8'h02)
            $fatal(1, "Curve did not advance on the CURVE_EARLY_MS boundary");
        reset_button;
        clocks(8 * FAST_STEP_MS * CLOCKS_MS);
        if (judged != end_judged || led !== 0) $fatal(1, "Reset pitch later produced a result");

        $display("PASS tb_baseball_top");
        $finish;
    end

    initial begin
        repeat (40000) @(posedge clk_sys);
        $fatal(1, "tb_baseball_top timeout");
    end
endmodule
