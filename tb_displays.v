`timescale 1ns/1ps
`include "baseball_defs.vh"

module tb_displays;
    reg clk_sys = 1'b0;
    always #5 clk_sys = ~clk_sys;

    reg rst = 1'b1;
    reg tick_ms = 1'b0;
    reg [15:0] scores = 16'd0;
    reg [2:0] bases = 3'd0;
    reg [12:0] lcd_state = 13'd0;
    wire [7:0] seg_com, seg_data;
    wire [2:0] base_lights;
    wire [127:0] line1, line2;
    wire [7:0] lcd_data;
    wire lcd_rs, lcd_rw, lcd_e;

    score_7seg score_dut (
        .clk_sys(clk_sys), .rst(rst), .tick_ms(tick_ms), .scores(scores),
        .seg_com(seg_com), .seg_data(seg_data)
    );
    base_lights_ctrl bases_dut (.bases(bases), .base_lights(base_lights));
    lcd_line_gen text_dut (.lcd_state(lcd_state), .line1(line1), .line2(line2));
    lcd_driver #(.CLK_HZ(1000000)) lcd_dut (
        .clk_sys(clk_sys), .rst(rst), .line1(line1), .line2(line2),
        .lcd_data(lcd_data), .lcd_rs(lcd_rs), .lcd_rw(lcd_rw), .lcd_e(lcd_e)
    );

    function [7:0] segments_for;
        input [3:0] digit;
        begin
            case (digit)
                4'd0: segments_for = 8'b00111111;
                4'd1: segments_for = 8'b00000110;
                4'd2: segments_for = 8'b01011011;
                4'd3: segments_for = 8'b01001111;
                4'd4: segments_for = 8'b01100110;
                4'd5: segments_for = 8'b01101101;
                4'd6: segments_for = 8'b01111101;
                4'd7: segments_for = 8'b00000111;
                4'd8: segments_for = 8'b01111111;
                4'd9: segments_for = 8'b01101111;
                default: segments_for = 8'bxxxxxxxx;
            endcase
        end
    endfunction

    task verify_score;
        input [15:0] score_pair;
        input [31:0] expected_digits;
        integer position;
        reg [7:0] expected_segments;
        begin
            scores = score_pair;
            for (position = 0; position < 8; position = position + 1) begin
                @(negedge clk_sys);
                expected_segments = segments_for(expected_digits[31 - position * 4 -: 4]);
                if (seg_com !== (8'd1 << position) || seg_data !== expected_segments)
                    $fatal(1, "score %h digit %0d: com=%h data=%h expected data=%h",
                           score_pair, position, seg_com, seg_data, expected_segments);
                tick_ms = 1'b1;
                @(negedge clk_sys);
                tick_ms = 1'b0;
                if (seg_com !== 8'd0)
                    $fatal(1, "score digit %0d: commons must blank before advancing, got %h",
                           position, seg_com);
            end
        end
    endtask

    task verify_bases;
        integer occupancy;
        begin
            for (occupancy = 0; occupancy < 8; occupancy = occupancy + 1) begin
                bases = occupancy[2:0];
                #1;
                if (base_lights !== bases)
                    $fatal(1, "base lights for occupancy %b: got %b", bases, base_lights);
            end
        end
    endtask

    localparam [127:0] TOP_TEXT = "P1 TOP B0 S0 O0 ";
    localparam [127:0] BOT_TEXT = "P2 BOT B3 S2 O1 ";
    localparam [127:0] HBP_TEXT = "HBP             ";
    localparam [127:0] LOOKING_TEXT = "LOOKING STRIKE  ";
    localparam [6:0] TOP_COUNTS = {1'b0, 2'd0, 2'd0, 2'd0};
    localparam [6:0] BOT_COUNTS = {1'b1, 2'd3, 2'd2, 2'd1};

    task verify_text;
        input [12:0] state_word;
        input [127:0] expected_line1, expected_line2;
        begin
            lcd_state = state_word;
            #1;
            if (line1 !== expected_line1 || line2 !== expected_line2)
                $fatal(1, "lcd state %h: got [%s][%s], expected [%s][%s]",
                       state_word, line1, line2, expected_line1, expected_line2);
        end
    endtask

    time bus_changed_at = 0;
    time prev_e_fall = 0;
    integer pulse_count = 0;
    always @(lcd_data or lcd_rs) bus_changed_at = $time;
    always @(posedge lcd_e) pulse_count = pulse_count + 1;

    // CLK_HZ=1 MHz makes one simulated clock represent one hardware microsecond.
    task expect_byte;
        input expected_rs;
        input [7:0] expected_data;
        input integer minimum_wait_us;
        time e_rising;
        begin
            @(posedge lcd_e);
            e_rising = $time;
            if (lcd_rw !== 1'b0 || lcd_rs !== expected_rs || lcd_data !== expected_data)
                $fatal(1, "lcd byte: got RW=%b RS=%b D=%h, expected RW=0 RS=%b D=%h",
                       lcd_rw, lcd_rs, lcd_data, expected_rs, expected_data);
            if (e_rising - prev_e_fall < minimum_wait_us * 10)
                $fatal(1, "lcd byte %h violates %0d us wait", expected_data, minimum_wait_us);
            if (e_rising - bus_changed_at < 10)
                $fatal(1, "lcd byte %h has less than one cycle of setup", expected_data);
            @(negedge lcd_e);
            if ($time - e_rising != 10 || bus_changed_at > e_rising)
                $fatal(1, "lcd byte %h: invalid E pulse width or unstable bus", expected_data);
            prev_e_fall = $time;
        end
    endtask

    task expect_frame;
        input [127:0] expected_line1, expected_line2;
        input change_mid_frame;
        integer character;
        begin
            expect_byte(1'b0, 8'h80, 50);
            for (character = 0; character < 16; character = character + 1) begin
                expect_byte(1'b1, expected_line1[127 - character * 8 -: 8], 50);
                if (change_mid_frame && character == 3)
                    verify_text({1'b0, `OUTCOME_PLAY, BOT_COUNTS, `RES_HBP}, BOT_TEXT, HBP_TEXT);
            end
            expect_byte(1'b0, 8'hc0, 50);
            for (character = 0; character < 16; character = character + 1)
                expect_byte(1'b1, expected_line2[127 - character * 8 -: 8], 50);
        end
    endtask

    task verify_lcd;
        begin
            prev_e_fall = $time;
            verify_text({1'b0, `OUTCOME_PLAY, TOP_COUNTS, `RES_NONE}, TOP_TEXT, "NO PITCH        ");
            verify_text({1'b0, `OUTCOME_PLAY, TOP_COUNTS, `RES_SWING_STRIKE},
                        TOP_TEXT, "SWING STRIKE    ");
            verify_text({1'b0, `OUTCOME_PLAY, BOT_COUNTS, `RES_BALL}, BOT_TEXT, "BALL            ");
            verify_text({1'b0, `OUTCOME_PLAY, BOT_COUNTS, `RES_HBP}, BOT_TEXT, HBP_TEXT);
            verify_text({1'b0, `OUTCOME_PLAY, BOT_COUNTS, `RES_SINGLE}, BOT_TEXT, "SINGLE          ");
            verify_text({1'b0, `OUTCOME_PLAY, BOT_COUNTS, `RES_DOUBLE}, BOT_TEXT, "DOUBLE          ");
            verify_text({1'b0, `OUTCOME_PLAY, BOT_COUNTS, `RES_HOMER}, BOT_TEXT, "HOME RUN        ");
            verify_text({1'b1, `OUTCOME_P1, BOT_COUNTS, `RES_HBP}, BOT_TEXT, "P1 WIN          ");
            verify_text({1'b1, `OUTCOME_P2, BOT_COUNTS, `RES_HBP}, BOT_TEXT, "P2 WIN          ");
            verify_text({1'b1, `OUTCOME_DRAW, BOT_COUNTS, `RES_HBP}, BOT_TEXT, "DRAW            ");
            verify_text({1'b0, `OUTCOME_PLAY, TOP_COUNTS, `RES_LOOKING_STRIKE},
                        TOP_TEXT, LOOKING_TEXT);

            expect_byte(1'b0, 8'h30, 50000);
            expect_byte(1'b0, 8'h30, 5000);
            expect_byte(1'b0, 8'h30, 150);
            expect_byte(1'b0, 8'h38, 50);
            expect_byte(1'b0, 8'h08, 50);
            expect_byte(1'b0, 8'h01, 50);
            expect_byte(1'b0, 8'h06, 2500);
            expect_byte(1'b0, 8'h0c, 50);
            expect_frame(TOP_TEXT, LOOKING_TEXT, 1'b1);
            expect_frame(BOT_TEXT, HBP_TEXT, 1'b0);
            repeat (200) @(negedge clk_sys);
            if (pulse_count != 76 || lcd_e !== 1'b0)
                $fatal(1, "stable LCD text generated extra writes, count=%0d", pulse_count);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk_sys);
        if (seg_com !== 8'd0 || lcd_e !== 1'b0 || lcd_rw !== 1'b0)
            $fatal(1, "display outputs invalid during reset");
        rst = 1'b0;
        fork
            begin
                verify_score(16'h7bff, 32'h01230255);
                verify_score(16'hc44e, 32'h01960078);
            end
            verify_bases;
            verify_lcd;
        join
        $display("PASS tb_displays: decimal scan, all base lights, LCD text and write timing/order");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "tb_displays watchdog expired");
    end
endmodule
