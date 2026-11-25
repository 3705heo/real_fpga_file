`timescale 1ns/1ps

module score_7seg (
    input  wire        clk_sys,
    input  wire        rst,
    input  wire        tick_ms,
    input  wire [15:0] scores,
    output wire [7:0]  seg_com,
    output reg  [7:0]  seg_data
);
    reg [2:0] digit_index;
    reg digit_on;
    wire [7:0] score = digit_index[2] ? scores[7:0] : scores[15:8];
    wire [11:0] bcd = to_bcd(score);
    reg [3:0] digit;

    // The eight shifts convert one unsigned score into three decimal digits.
    function [11:0] to_bcd;
        input [7:0] value;
        integer bit_index;
        reg [11:0] work_bcd;
        begin
            work_bcd = 12'd0;
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                if (work_bcd[3:0] >= 4'd5)
                    work_bcd[3:0] = work_bcd[3:0] + 4'd3;
                if (work_bcd[7:4] >= 4'd5)
                    work_bcd[7:4] = work_bcd[7:4] + 4'd3;
                if (work_bcd[11:8] >= 4'd5)
                    work_bcd[11:8] = work_bcd[11:8] + 4'd3;
                work_bcd = {work_bcd[10:0], value[bit_index]};
            end
            to_bcd = work_bcd;
        end
    endfunction

    // Switch all commons off for one system clock as the segment data changes.
    always @(posedge clk_sys) begin
        if (rst) begin
            digit_index <= 3'd0;
            digit_on <= 1'b0;
        end else if (!digit_on) begin
            digit_on <= 1'b1;
        end else if (tick_ms) begin
            digit_index <= digit_index + 3'd1;
            digit_on <= 1'b0;
        end
    end

    // Logical common 0 is leftmost. Bit 7 is DP, and bits 6:0 are G..A.
    assign seg_com = digit_on ? (8'b00000001 << digit_index) : 8'b0;

    always @* begin
        case (digit_index[1:0])
            2'd0: digit = 4'd0;
            2'd1: digit = bcd[11:8];
            2'd2: digit = bcd[7:4];
            default: digit = bcd[3:0];
        endcase
        case (digit)
            4'd0: seg_data = 8'h3f;
            4'd1: seg_data = 8'h06;
            4'd2: seg_data = 8'h5b;
            4'd3: seg_data = 8'h4f;
            4'd4: seg_data = 8'h66;
            4'd5: seg_data = 8'h6d;
            4'd6: seg_data = 8'h7d;
            4'd7: seg_data = 8'h07;
            4'd8: seg_data = 8'h7f;
            4'd9: seg_data = 8'h6f;
            default: seg_data = 8'h00;
        endcase
    end
endmodule
