`timescale 1ns/1ps
`include "baseball_defs.vh"

module pitch_engine #(
    parameter integer FAST_STEP_MS = 220,
    parameter integer CURVE_LATE_MS = 120,
    parameter integer CURVE_EARLY_MS = 300
) (
    input wire clk_sys,
    input wire rst,
    input wire tick_ms,
    input wire [3:0] pitch_ctrl,
    output wire [7:0] led,
    output wire [7:0] pitch_bus
);
    function integer count_width;
        input integer value;
        begin
            count_width = 1;
            while (value > 1) begin
                value = value >> 1;
                count_width = count_width + 1;
            end
        end
    endfunction

    localparam integer MAX_CURVE_STEP_MS =
        (CURVE_EARLY_MS > CURVE_LATE_MS) ? CURVE_EARLY_MS : CURVE_LATE_MS;
    localparam integer MAX_STEP_MS =
        (FAST_STEP_MS > MAX_CURVE_STEP_MS) ? FAST_STEP_MS : MAX_CURVE_STEP_MS;
    localparam integer COUNT_WIDTH = count_width(MAX_STEP_MS - 1);
    localparam [COUNT_WIDTH-1:0] LAST_FAST_TICK = FAST_STEP_MS - 1;
    localparam [COUNT_WIDTH-1:0] LAST_CURVE_EARLY_TICK = CURVE_EARLY_MS - 1;
    localparam [COUNT_WIDTH-1:0] LAST_CURVE_LATE_TICK = CURVE_LATE_MS - 1;
    reg active;
    reg [1:0] pitch_type;
    reg [3:0] position;
    reg [COUNT_WIDTH-1:0] elapsed;

    wire stop = pitch_ctrl[2];
    wire launch = !rst && !active && pitch_ctrl[3] && !stop;
    wire [COUNT_WIDTH-1:0] curve_last_tick =
        (position >= 4'd6) ? LAST_CURVE_LATE_TICK : LAST_CURVE_EARLY_TICK;
    wire [COUNT_WIDTH-1:0] last_tick =
        (pitch_type == `PITCH_CURVE) ? curve_last_tick : LAST_FAST_TICK;
    wire step_due = active && tick_ms && (elapsed == last_tick);
    wire last_step = !rst && !stop && step_due && (position == 4'd8);

    // Launch uses position 0 before the edge that first lights LED 1.
    // The terminal flag is visible with position 8 before its closing edge.
    assign pitch_bus = {active | launch, last_step,
                        launch ? pitch_ctrl[1:0] : pitch_type, position};
    assign led = (active && !stop && !rst) ?
                 (8'b00000001 << (position - 4'd1)) : 8'b0;

    always @(posedge clk_sys) begin
        if (rst || stop) begin
            active <= 1'b0;
            pitch_type <= `PITCH_FAST;
            position <= 4'd0;
            elapsed <= {COUNT_WIDTH{1'b0}};
        end else if (launch) begin
            active <= 1'b1;
            pitch_type <= pitch_ctrl[1:0];
            position <= 4'd1;
            elapsed <= {COUNT_WIDTH{1'b0}};
        end else if (step_due) begin
            elapsed <= {COUNT_WIDTH{1'b0}};
            if (position == 4'd8) begin
                active <= 1'b0;
                position <= 4'd0;
            end else begin
                position <= position + 1'b1;
            end
        end else if (active && tick_ms) begin
            elapsed <= elapsed + 1'b1;
        end
    end
endmodule
