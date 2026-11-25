`timescale 1ns/1ps
`include "baseball_defs.vh"

module button_input #(
    parameter integer DEBOUNCE_MS = 20
) (
    input wire clk_sys,
    input wire tick_ms,
    input wire [4:0] buttons,
    input wire swing_window,
    output reg pitch_req,
    output reg [1:0] pitch_sel,
    output wire swing_pulse,
    output wire rst
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

    localparam integer COUNT_WIDTH = count_width(DEBOUNCE_MS - 1);
    localparam [COUNT_WIDTH-1:0] LAST_SAMPLE = DEBOUNCE_MS - 1;
    (* ASYNC_REG = "TRUE" *) reg [4:0] sync_meta = 5'b0;
    (* ASYNC_REG = "TRUE" *) reg [4:0] sync_sample = 5'b0;
    reg swing_window_meta = 1'b0;
    reg swing_window_sample = 1'b0;
    reg [3:0] power_on = 4'b1111;
    reg swing_contact = 1'b0;
    reg swing_eligible = 1'b0;
    reg [COUNT_WIDTH-1:0] swing_release_samples = {COUNT_WIDTH{1'b0}};
    wire [4:0] stable;
    wire [3:0] pressed;
    wire swing_released = swing_contact && !sync_sample[0] && tick_ms &&
                          (swing_release_samples == LAST_SAMPLE);

    // Spartan-7 configuration initializes these registers. Debouncing continues
    // during reset so a debounced reset release and held-button tracking work.
    always @(posedge clk_sys) begin
        sync_meta <= buttons;
        sync_sample <= sync_meta;
        swing_window_meta <= swing_window;
        swing_window_sample <= swing_window_meta;
        power_on <= {power_on[2:0], 1'b0};
    end

    assign rst = power_on[3] | stable[4];
    assign swing_pulse = !rst && pressed[0] && swing_eligible;

    // Carry the pitch window through the same two stages as SW_0 so the
    // first sampled high determines eligibility. Debounce the release
    // before a new contact can qualify.
    always @(posedge clk_sys) begin
        if (!swing_contact && sync_sample[0]) begin
            swing_contact <= 1'b1;
            swing_eligible <= swing_window_sample && swing_window && !rst;
        end else if (swing_released) begin
            swing_contact <= 1'b0;
            swing_eligible <= 1'b0;
        end else if (rst || !swing_window) begin
            swing_eligible <= 1'b0;
        end

        if (tick_ms) begin
            if (!swing_contact || sync_sample[0] || swing_released)
                swing_release_samples <= {COUNT_WIDTH{1'b0}};
            else
                swing_release_samples <= swing_release_samples + 1'b1;
        end
    end

    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin : debounce
            reg [COUNT_WIDTH-1:0] samples = {COUNT_WIDTH{1'b0}};
            reg stable_level = 1'b0;

            always @(posedge clk_sys) begin
                if (tick_ms) begin
                    if (sync_sample[i] == stable_level) begin
                        samples <= {COUNT_WIDTH{1'b0}};
                    end else if (samples == LAST_SAMPLE) begin
                        samples <= {COUNT_WIDTH{1'b0}};
                        stable_level <= sync_sample[i];
                    end else begin
                        samples <= samples + 1'b1;
                    end
                end
            end

            assign stable[i] = stable_level;
            if (i < 4) begin : gameplay_button
                reg press_event = 1'b0;
                always @(posedge clk_sys)
                    press_event <= !rst && tick_ms && sync_sample[i] && !stable_level &&
                                   (samples == LAST_SAMPLE);
                assign pressed[i] = press_event;
            end
        end
    endgenerate

    // Decode only exact one-hot press events. Held buttons never repeat.
    always @* begin
        pitch_req = 1'b0;
        pitch_sel = `PITCH_FAST;
        if (!rst) begin
            case (pressed[3:1])
                3'b001: begin
                    pitch_req = 1'b1;
                    pitch_sel = `PITCH_FAST;
                end
                3'b010: begin
                    pitch_req = 1'b1;
                    pitch_sel = `PITCH_CURVE;
                end
                3'b100: begin
                    pitch_req = 1'b1;
                    pitch_sel = `PITCH_BALL;
                end
                default: begin
                    pitch_req = 1'b0;
                end
            endcase
        end
    end
endmodule
