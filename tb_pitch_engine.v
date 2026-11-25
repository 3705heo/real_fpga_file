`timescale 1ns/1ps
`include "baseball_defs.vh"

module tb_pitch_engine;
    localparam integer FAST_MS = 3;
    localparam integer CURVE_EARLY_MS = 5;
    localparam integer CURVE_LATE_MS = 1;
    localparam integer FAST_TOTAL = 8 * FAST_MS;
    localparam integer CURVE_EARLY_TOTAL = 5 * CURVE_EARLY_MS;
    localparam integer CURVE_TOTAL = CURVE_EARLY_TOTAL + (3 * CURVE_LATE_MS);

    reg clk_sys = 1'b0;
    reg rst = 1'b1;
    reg tick_ms = 1'b0;
    reg [3:0] fast_ctrl = 4'b0;
    reg [3:0] ball_ctrl = 4'b0;
    reg [3:0] curve_ctrl = 4'b0;
    wire [7:0] fast_led, ball_led, curve_led;
    wire [7:0] fast_bus, ball_bus, curve_bus;
    integer elapsed;
    integer fast_pos, curve_pos;

    always #5 clk_sys = ~clk_sys;

    pitch_engine #(
        .FAST_STEP_MS(FAST_MS), .CURVE_EARLY_MS(CURVE_EARLY_MS), .CURVE_LATE_MS(CURVE_LATE_MS)
    ) fast_dut (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms),
        .pitch_ctrl(fast_ctrl), .led(fast_led), .pitch_bus(fast_bus)
    );
    pitch_engine #(
        .FAST_STEP_MS(FAST_MS), .CURVE_EARLY_MS(CURVE_EARLY_MS), .CURVE_LATE_MS(CURVE_LATE_MS)
    ) ball_dut (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms),
        .pitch_ctrl(ball_ctrl), .led(ball_led), .pitch_bus(ball_bus)
    );
    pitch_engine #(
        .FAST_STEP_MS(FAST_MS), .CURVE_EARLY_MS(CURVE_EARLY_MS), .CURVE_LATE_MS(CURVE_LATE_MS)
    ) curve_dut (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms),
        .pitch_ctrl(curve_ctrl), .led(curve_led), .pitch_bus(curve_bus)
    );

    task check_position;
        input [8*8-1:0] label;
        input [7:0] bus;
        input [7:0] led;
        input [1:0] pitch_type;
        input integer position;
        input end_due;
        reg [7:0] expected_led;
        begin
            expected_led = (position > 0) ? (8'b1 << (position - 1)) : 8'b0;
            if ((led !== expected_led) ||
                (bus !== {(position != 0), end_due, pitch_type, position[3:0]}))
                $fatal(1, "%0s tick %0d: expected position %0d LED %b end %b, got LED %b bus %b",
                       label, elapsed, position, expected_led, end_due, led, bus);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk_sys);
        @(negedge clk_sys);
        rst = 1'b0;
        fast_ctrl = {2'b10, `PITCH_FAST};
        ball_ctrl = {2'b10, `PITCH_BALL};
        curve_ctrl = {2'b10, `PITCH_CURVE};
        #1;
        if (({fast_led, ball_led, curve_led} !== 24'b0) ||
            (fast_bus !== {2'b10, `PITCH_FAST, 4'd0}) ||
            (ball_bus !== {2'b10, `PITCH_BALL, 4'd0}) ||
            (curve_bus !== {2'b10, `PITCH_CURVE, 4'd0}))
            $fatal(1, "Launch preview must announce position 0 while LEDs remain off");

        @(posedge clk_sys);
        @(negedge clk_sys);
        fast_ctrl = 4'b0;
        ball_ctrl = 4'b0;
        curve_ctrl = 4'b0;
        elapsed = 0;
        repeat (3) @(negedge clk_sys);
        check_position("fast", fast_bus, fast_led, `PITCH_FAST, 1, 1'b0);
        check_position("ball", ball_bus, ball_led, `PITCH_BALL, 1, 1'b0);
        check_position("curve", curve_bus, curve_led, `PITCH_CURVE, 1, 1'b0);

        for (elapsed = 0; elapsed <= CURVE_TOTAL; elapsed = elapsed + 1) begin
            fast_pos = (elapsed < FAST_TOTAL) ? (elapsed / FAST_MS + 1) : 0;
            if (elapsed < CURVE_EARLY_TOTAL)
                curve_pos = elapsed / CURVE_EARLY_MS + 1;
            else if (elapsed < CURVE_TOTAL)
                curve_pos = (elapsed - CURVE_EARLY_TOTAL) / CURVE_LATE_MS + 6;
            else
                curve_pos = 0;

            tick_ms = 1'b1;
            #1;
            check_position("fast", fast_bus, fast_led, `PITCH_FAST, fast_pos, elapsed == FAST_TOTAL - 1);
            check_position("ball", ball_bus, ball_led, `PITCH_BALL, fast_pos, elapsed == FAST_TOTAL - 1);
            check_position("curve", curve_bus, curve_led, `PITCH_CURVE, curve_pos, elapsed == CURVE_TOTAL - 1);
            if ((fast_led !== ball_led) || (fast_bus[7:6] !== ball_bus[7:6]))
                $fatal(1, "Fastball and ball differ at tick %0d", elapsed);
            if ((elapsed == FAST_TOTAL) && ({curve_bus[7], fast_bus[7]} !== 2'b10))
                $fatal(1, "Curve should remain in flight after the fastball ends");
            @(negedge clk_sys);
        end

        tick_ms = 1'b0;
        fast_ctrl = {2'b10, `PITCH_FAST};
        @(negedge clk_sys);
        if (fast_led !== 8'b1)
            $fatal(1, "Second pitch did not reach LED 1");
        fast_ctrl = {2'b11, `PITCH_BALL};
        @(negedge clk_sys);
        if ((fast_led !== 8'b0) || (fast_bus[7:6] !== 2'b00))
            $fatal(1, "Stop did not take precedence over start");
        fast_ctrl = {2'b10, `PITCH_FAST};
        @(negedge clk_sys);
        fast_ctrl = 4'b0;
        rst = 1'b1;
        @(negedge clk_sys);
        if ((fast_led !== 8'b0) || (fast_bus !== 8'b0))
            $fatal(1, "Reset did not clear active pitch");

        $display("PASS tb_pitch_engine");
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "Timeout in tb_pitch_engine");
    end
endmodule
