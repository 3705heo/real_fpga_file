`timescale 1ns/1ps
`include "baseball_defs.vh"

module tb_effect_ctrl;
    reg clk_sys = 1'b0;
    always #5 clk_sys = ~clk_sys;

    reg rst = 1'b1;
    reg tick_ms = 1'b0;
    reg [1:0] fx_evt = `FX_NONE;
    wire piezo;
    wire [3:0] rgb_r, rgb_g, rgb_b;

    effect_ctrl #(
        .CLK_HZ(24000), .PREP_MS(3), .HOMER_MS(9), .BLINK_MS(2),
        .PREP_HZ(3000), .HOMER_LOW_HZ(1000), .HOMER_MID_HZ(1500), .HOMER_HIGH_HZ(2000)
    ) dut (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms), .fx_evt(fx_evt),
        .piezo(piezo), .rgb_r(rgb_r), .rgb_g(rgb_g), .rgb_b(rgb_b)
    );

    task expect_color;
        input on;
        reg [11:0] expected;
        begin
            expected = on ? 12'hff0 : 12'h000;
            if ({rgb_r, rgb_g, rgb_b} !== expected)
                $fatal(1, "RGB expected %h, got %h at %0t", expected, {rgb_r, rgb_g, rgb_b}, $time);
        end
    endtask

    task fire_event;
        input [1:0] event_code;
        begin
            @(negedge clk_sys);
            fx_evt = event_code;
            // The event edge does not count as an elapsed millisecond.
            tick_ms = 1'b1;
            @(negedge clk_sys);
            fx_evt = `FX_NONE;
            tick_ms = 1'b0;
        end
    endtask

    task advance_ms;
        input expected_color;
        begin
            @(negedge clk_sys);
            tick_ms = 1'b1;
            @(negedge clk_sys);
            tick_ms = 1'b0;
            expect_color(expected_color);
        end
    endtask

    task expect_tone;
        input integer half_period_cycles;
        time rise_at, fall_at;
        begin
            @(posedge piezo);
            rise_at = $time;
            @(negedge piezo);
            fall_at = $time;
            if (fall_at - rise_at != 10 * half_period_cycles)
                $fatal(1, "piezo high width: got %0t, expected %0d cycles", fall_at - rise_at, half_period_cycles);
            @(posedge piezo);
            if ($time - fall_at != 10 * half_period_cycles)
                $fatal(1, "piezo low width: got %0t, expected %0d cycles", $time - fall_at, half_period_cycles);
        end
    endtask

    task expect_quiet;
        integer cycle_index;
        begin
            for (cycle_index = 0; cycle_index < 30; cycle_index = cycle_index + 1) begin
                if (piezo !== 1'b0)
                    $fatal(1, "piezo must remain low when idle, got %b at %0t", piezo, $time);
                expect_color(1'b0);
                @(negedge clk_sys);
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk_sys);
        rst = 1'b0;
        expect_quiet;

        fire_event(`FX_PREP);
        expect_color(1'b0);
        expect_tone(4);
        advance_ms(1'b0);
        advance_ms(1'b0);
        expect_tone(4);
        advance_ms(1'b0);
        expect_quiet;

        fire_event(`FX_HOMER);
        expect_color(1'b1);
        expect_tone(12);
        advance_ms(1'b1);
        advance_ms(1'b0);
        advance_ms(1'b0);
        expect_tone(8);
        advance_ms(1'b1);
        advance_ms(1'b1);
        advance_ms(1'b0);
        expect_tone(6);
        advance_ms(1'b0);
        advance_ms(1'b1);
        advance_ms(1'b0);
        expect_quiet;

        fire_event(`FX_HOMER);
        expect_color(1'b1);
        @(posedge piezo);
        @(negedge clk_sys);
        rst = 1'b1;
        @(negedge clk_sys);
        rst = 1'b0;
        expect_quiet;

        $display("PASS tb_effect_ctrl: preparation, three home run notes, blinking and reset");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "tb_effect_ctrl watchdog expired");
    end
endmodule
