`timescale 1ns/1ps
`include "baseball_defs.vh"

module effect_ctrl #(
    parameter integer CLK_HZ = 50000000,
    parameter integer PREP_MS = 300,
    parameter integer HOMER_MS = 900,
    parameter integer BLINK_MS = 125,
    parameter integer PREP_HZ = 1500,
    parameter integer HOMER_LOW_HZ = 523,
    parameter integer HOMER_MID_HZ = 659,
    parameter integer HOMER_HIGH_HZ = 784
) (
    input  wire       clk_sys,
    input  wire       rst,
    input  wire       tick_ms,
    input  wire [1:0] fx_evt,
    output wire       piezo,
    output wire [3:0] rgb_r,
    output wire [3:0] rgb_g,
    output wire [3:0] rgb_b
);
    function integer half_period;
        input integer tone_hz;
        integer cycles;
        begin
            cycles = CLK_HZ / (2 * tone_hz);
            half_period = (cycles < 1) ? 1 : cycles;
        end
    endfunction

    localparam integer PREP_HALF = half_period(PREP_HZ);
    localparam integer HOMER_LOW_HALF = half_period(HOMER_LOW_HZ);
    localparam integer HOMER_MID_HALF = half_period(HOMER_MID_HZ);
    localparam integer HOMER_HIGH_HALF = half_period(HOMER_HIGH_HZ);
    localparam integer FIRST_NOTE_END = (HOMER_MS + 2) / 3;
    localparam integer SECOND_NOTE_END = (2 * HOMER_MS + 2) / 3;

    reg [1:0] effect;
    reg [31:0] elapsed_ms;
    reg [31:0] blink_count;
    reg [31:0] tone_count;
    reg [31:0] tone_half_period;
    reg tone_high;
    reg blink_on;

    wire [31:0] duration_ms = (effect == `FX_PREP) ? PREP_MS : HOMER_MS;
    wire color_on = (effect == `FX_HOMER) && blink_on;
    assign piezo = (effect != `FX_NONE) && tone_high;
    assign rgb_r = {4{color_on}};
    assign rgb_g = {4{color_on}};
    assign rgb_b = 4'b0;

    always @* begin
        if (effect == `FX_PREP)
            tone_half_period = PREP_HALF;
        else if (elapsed_ms < FIRST_NOTE_END)
            tone_half_period = HOMER_LOW_HALF;
        else if (elapsed_ms < SECOND_NOTE_END)
            tone_half_period = HOMER_MID_HALF;
        else
            tone_half_period = HOMER_HIGH_HALF;
    end

    always @(posedge clk_sys) begin
        if (rst) begin
            effect <= `FX_NONE;
            elapsed_ms <= 32'd0;
            blink_count <= 32'd0;
            tone_count <= 32'd0;
            tone_high <= 1'b0;
            blink_on <= 1'b0;
        end else if ((fx_evt == `FX_PREP) || (fx_evt == `FX_HOMER)) begin
            effect <= fx_evt;
            elapsed_ms <= 32'd0;
            blink_count <= 32'd0;
            tone_count <= 32'd0;
            tone_high <= 1'b0;
            blink_on <= 1'b1;
        end else if (effect != `FX_NONE) begin
            if (tick_ms) begin
                if (elapsed_ms >= duration_ms - 32'd1)
                    effect <= `FX_NONE;
                else
                    elapsed_ms <= elapsed_ms + 32'd1;

                if (effect == `FX_HOMER) begin
                    if (blink_count >= BLINK_MS - 1) begin
                        blink_count <= 32'd0;
                        blink_on <= ~blink_on;
                    end else begin
                        blink_count <= blink_count + 32'd1;
                    end
                end
            end

            if (tone_count >= tone_half_period - 32'd1) begin
                tone_count <= 32'd0;
                tone_high <= ~tone_high;
            end else begin
                tone_count <= tone_count + 32'd1;
            end
        end
    end
endmodule
