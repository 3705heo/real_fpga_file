`timescale 1ns/1ps
`include "baseball_defs.vh"

module tb_button_input;
    reg clk_sys = 1'b0;
    reg [4:0] buttons = 5'b0;
    reg swing_window = 1'b1;
    wire tick_ms;
    wire fractional_tick;
    wire rst;
    wire pitch_req;
    wire [1:0] pitch_sel;
    wire swing_pulse;
    integer fast_presses = 0;
    integer curve_presses = 0;
    integer ball_presses = 0;
    integer swings = 0;
    integer k;
    integer fractional_count = 0;
    reg previous_tick = 1'b0;
    reg previous_pitch = 1'b0;
    reg previous_swing = 1'b0;

    always #5 clk_sys = ~clk_sys;

    tick_gen #(.CLK_HZ(2000)) regular_ticks (
        .clk_sys(clk_sys), .rst(1'b0), .tick_ms(tick_ms)
    );
    tick_gen #(.CLK_HZ(2500)) fractional_ticks (
        .clk_sys(clk_sys), .rst(1'b0), .tick_ms(fractional_tick)
    );
    button_input #(.DEBOUNCE_MS(3)) dut (
        .clk_sys(clk_sys), .tick_ms(tick_ms), .buttons(buttons),
        .swing_window(swing_window),
        .pitch_req(pitch_req), .pitch_sel(pitch_sel),
        .swing_pulse(swing_pulse), .rst(rst)
    );

    always @(posedge clk_sys) begin
        #1;
        if (pitch_req && previous_pitch)
            $fatal(1, "Pitch pulse exceeded one clock");
        if (swing_pulse && previous_swing)
            $fatal(1, "Swing pulse exceeded one clock");
        previous_pitch = pitch_req;
        previous_swing = swing_pulse;
        if (pitch_req) begin
            case (pitch_sel)
                `PITCH_FAST: fast_presses = fast_presses + 1;
                `PITCH_CURVE: curve_presses = curve_presses + 1;
                `PITCH_BALL: ball_presses = ball_presses + 1;
                default: $fatal(1, "Unknown pitch_sel %b during pitch_req", pitch_sel);
            endcase
        end
        if (swing_pulse)
            swings = swings + 1;
    end

    task drive;
        input [4:0] values;
        input integer duration;
        begin
            @(negedge clk_sys);
            buttons = values;
            repeat (duration) @(negedge clk_sys);
        end
    endtask

    task expect_counts;
        input integer fast_count;
        input integer curve_count;
        input integer ball_count;
        input integer swing_count;
        begin
            if ((fast_presses != fast_count) || (curve_presses != curve_count) ||
                (ball_presses != ball_count) || (swings != swing_count))
                $fatal(1, "At %0t fast/curve/ball/swing=%0d/%0d/%0d/%0d expected %0d/%0d/%0d/%0d",
                       $time, fast_presses, curve_presses, ball_presses, swings,
                       fast_count, curve_count, ball_count, swing_count);
        end
    endtask

    initial begin
        for (k = 0; k < 100; k = k + 1) begin
            @(posedge clk_sys);
            if (fractional_tick && previous_tick)
                $fatal(1, "Fractional tick exceeded one clock");
            if (fractional_tick)
                fractional_count = fractional_count + 1;
            previous_tick = fractional_tick;
        end
        if (fractional_count != 40)
            $fatal(1, "2500 Hz phase accumulator yielded %0d ticks per 100 clocks", fractional_count);
    end

    initial begin
        #1;
        if (rst !== 1'b1)
            $fatal(1, "Power-on reset did not assert");
        drive(5'b00000, 12);
        if (rst !== 1'b0)
            $fatal(1, "Power-on reset did not release");

        drive(5'b00011, 1);
        drive(5'b00000, 2);
        drive(5'b00011, 1);
        drive(5'b00000, 10);
        expect_counts(0, 0, 0, 0);

        drive(5'b00011, 20);
        expect_counts(1, 0, 0, 1);
        drive(5'b00000, 1);
        drive(5'b00011, 18);
        expect_counts(1, 0, 0, 1);
        drive(5'b00000, 12);
        drive(5'b00011, 12);
        expect_counts(2, 0, 0, 2);

        drive(5'b00000, 12);
        drive(5'b01110, 18);
        expect_counts(2, 0, 0, 2);
        drive(5'b00100, 18);
        expect_counts(2, 0, 0, 2);
        drive(5'b00000, 12);
        drive(5'b00100, 15);
        expect_counts(2, 1, 0, 2);
        drive(5'b00000, 12);
        drive(5'b01000, 15);
        expect_counts(2, 1, 1, 2);

        drive(5'b00000, 12);
        drive(5'b10000, 1);
        drive(5'b00000, 12);
        if (rst !== 1'b0)
            $fatal(1, "Reset noise passed debounce");
        drive(5'b10011, 15);
        if (rst !== 1'b1)
            $fatal(1, "Reset did not assert with simultaneous gameplay inputs");
        expect_counts(2, 1, 1, 2);
        drive(5'b00011, 15);
        if (rst !== 1'b0)
            $fatal(1, "Debounced reset did not release");
        expect_counts(2, 1, 1, 2);
        drive(5'b00000, 12);
        drive(5'b00011, 12);
        expect_counts(3, 1, 1, 3);

        // The raw press starts before LED 1, but its debounce would finish
        // after launch. Bounce after launch must not requalify that contact.
        drive(5'b00000, 12);
        swing_window = 1'b0;
        drive(5'b00001, 2);
        swing_window = 1'b1;
        drive(5'b00000, 1);
        drive(5'b00001, 15);
        expect_counts(3, 1, 1, 3);
        drive(5'b00000, 12);
        drive(5'b00001, 12);
        expect_counts(3, 1, 1, 4);

        // Closing the window revokes a previously eligible contact even
        // if the window reopens before that held press finishes debouncing.
        drive(5'b00000, 12);
        drive(5'b00001, 4);
        swing_window = 1'b0;
        @(negedge clk_sys);
        swing_window = 1'b1;
        drive(5'b00001, 15);
        expect_counts(3, 1, 1, 4);

        $display("PASS tb_button_input");
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "Timeout in tb_button_input");
    end
endmodule
