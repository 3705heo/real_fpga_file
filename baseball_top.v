`timescale 1ns/1ps

module baseball_top #(
    parameter integer CLK_HZ = 50000000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer PREP_MS = 300,
    parameter integer FAST_STEP_MS = 220,
    parameter integer CURVE_LATE_MS = 120,
    parameter integer RESULT_MS = 950,
    parameter [15:0] HBP_SEED = 16'h1ace,
    parameter integer HBP_THRESHOLD = 9830,
    parameter integer HOMER_MS = 900,
    parameter [4:0] BUTTON_INVERT = 5'b00000,
    parameter [7:0] LED_INVERT = 8'h00,
    parameter [7:0] SEG_COM_INVERT = 8'h00,
    parameter [7:0] SEG_DATA_INVERT = 8'h00,
    parameter integer SEG_REVERSE = 0,
    parameter [2:0] BASE_INVERT = 3'b000,
    parameter [3:0] RGB_R_INVERT = 4'h0,
    parameter [3:0] RGB_G_INVERT = 4'h0,
    parameter [3:0] RGB_B_INVERT = 4'h0,
    parameter integer PIEZO_INVERT = 0,
    parameter [7:0] LCD_DATA_INVERT = 8'h00,
    parameter [2:0] LCD_CTRL_INVERT = 3'b000,
    parameter integer CURVE_EARLY_MS = 300
) (
    input  wire       clk_sys,
    input  wire       sw_0,
    input  wire       sw_1,
    input  wire       sw_2,
    input  wire       sw_3,
    input  wire       sw_star,
    output wire [7:0] led,
    output wire [7:0] seg_com,
    output wire [7:0] seg_data,
    output wire [2:0] base_lights,
    output wire       piezo,
    output wire [3:0] rgb_r,
    output wire [3:0] rgb_g,
    output wire [3:0] rgb_b,
    output wire [7:0] lcd_data,
    output wire       lcd_rs,
    output wire       lcd_rw,
    output wire       lcd_e
);
    wire [4:0] buttons;
    wire rst;
    wire tick_ms;
    wire pitch_req;
    wire [1:0] pitch_sel;
    wire swing_pulse;
    wire swing_window;
    wire [3:0] pitch_ctrl;
    wire [7:0] pitch_bus;
    wire hbp_candidate;
    wire result_valid;
    wire [2:0] result_code;
    wire [5:0] runner_req;
    wire [5:0] runner_res;
    wire [15:0] scores;
    wire [2:0] bases;
    wire [12:0] lcd_state;
    wire [1:0] fx_evt;
    wire [127:0] line1;
    wire [127:0] line2;

    wire [7:0] led_on;
    wire [7:0] seg_com_on;
    wire [7:0] seg_data_on;
    wire [2:0] base_on;
    wire piezo_on;
    wire [3:0] red_on;
    wire [3:0] green_on;
    wire [3:0] blue_on;
    wire [7:0] lcd_data_raw;
    wire lcd_rs_raw, lcd_rw_raw, lcd_e_raw;

    assign buttons = {sw_star, sw_3, sw_2, sw_1, sw_0} ^ BUTTON_INVERT;
    assign swing_window = pitch_bus[7] && (pitch_bus[3:0] != 4'd0) && !result_valid;
    assign led = led_on ^ LED_INVERT;
    assign seg_data = seg_data_on ^ SEG_DATA_INVERT;
    assign base_lights = base_on ^ BASE_INVERT;
    assign piezo = piezo_on ^ (PIEZO_INVERT != 0);
    assign rgb_r = red_on ^ RGB_R_INVERT;
    assign rgb_g = green_on ^ RGB_G_INVERT;
    assign rgb_b = blue_on ^ RGB_B_INVERT;
    assign lcd_data = lcd_data_raw ^ LCD_DATA_INVERT;
    assign {lcd_rs, lcd_rw, lcd_e} = {lcd_rs_raw, lcd_rw_raw, lcd_e_raw} ^ LCD_CTRL_INVERT;

    genvar digit;
    generate
        for (digit = 0; digit < 8; digit = digit + 1) begin : map_digits
            localparam integer LOGICAL_DIGIT = SEG_REVERSE ? (7 - digit) : digit;
            assign seg_com[digit] = seg_com_on[LOGICAL_DIGIT] ^ SEG_COM_INVERT[digit];
        end
    endgenerate

    // Keep time running while reset is held so the reset button can debounce its release.
    tick_gen #(.CLK_HZ(CLK_HZ)) clock_enable (
        .clk_sys(clk_sys), .rst(1'b0), .tick_ms(tick_ms)
    );
    button_input #(.DEBOUNCE_MS(DEBOUNCE_MS)) input_buttons (
        .clk_sys(clk_sys), .tick_ms(tick_ms), .buttons(buttons),
        .swing_window(swing_window), .rst(rst),
        .pitch_req(pitch_req), .pitch_sel(pitch_sel), .swing_pulse(swing_pulse)
    );
    pitch_engine #(
        .FAST_STEP_MS(FAST_STEP_MS),
        .CURVE_EARLY_MS(CURVE_EARLY_MS),
        .CURVE_LATE_MS(CURVE_LATE_MS)
    ) pitch (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms),
        .pitch_ctrl(pitch_ctrl), .led(led_on), .pitch_bus(pitch_bus)
    );
    hbp_rng #(.HBP_SEED(HBP_SEED), .HBP_THRESHOLD(HBP_THRESHOLD)) random_hbp (
        .clk_sys(clk_sys), .rst(rst), .hbp_candidate(hbp_candidate)
    );
    hit_judge judge (
        .clk_sys(clk_sys), .rst(rst), .pitch_bus(pitch_bus),
        .swing_pulse(swing_pulse), .hbp_candidate(hbp_candidate),
        .result_valid(result_valid), .result_code(result_code)
    );
    runner_update runners (.runner_req(runner_req), .runner_res(runner_res));
    game_manager #(.PREP_MS(PREP_MS), .RESULT_MS(RESULT_MS)) game (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms),
        .pitch_req(pitch_req), .pitch_sel(pitch_sel),
        .result_valid(result_valid), .result_code(result_code),
        .runner_res(runner_res), .pitch_ctrl(pitch_ctrl), .runner_req(runner_req),
        .scores(scores), .bases(bases), .lcd_state(lcd_state), .fx_evt(fx_evt)
    );
    score_7seg score_display (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms), .scores(scores),
        .seg_com(seg_com_on), .seg_data(seg_data_on)
    );
    base_lights_ctrl bases_display (.bases(bases), .base_lights(base_on));
    lcd_line_gen text_lines (.lcd_state(lcd_state), .line1(line1), .line2(line2));
    lcd_driver #(.CLK_HZ(CLK_HZ)) text_lcd (
        .clk_sys(clk_sys), .rst(rst), .line1(line1), .line2(line2),
        .lcd_data(lcd_data_raw), .lcd_rs(lcd_rs_raw), .lcd_rw(lcd_rw_raw), .lcd_e(lcd_e_raw)
    );
    effect_ctrl #(.CLK_HZ(CLK_HZ), .PREP_MS(PREP_MS), .HOMER_MS(HOMER_MS)) effects (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms), .fx_evt(fx_evt),
        .piezo(piezo_on), .rgb_r(red_on), .rgb_g(green_on), .rgb_b(blue_on)
    );
endmodule
