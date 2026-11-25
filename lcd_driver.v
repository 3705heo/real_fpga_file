`timescale 1ns/1ps

module lcd_driver #(
    parameter integer CLK_HZ = 50000000
) (
    input  wire         clk_sys,
    input  wire         rst,
    input  wire [127:0] line1,
    input  wire [127:0] line2,
    output reg  [7:0]   lcd_data,
    output reg          lcd_rs,
    output wire         lcd_rw,
    output reg          lcd_e
);
    // HD44780-compatible 8-bit write-only protocol. Round all waits upward.
    function integer clocks_for_us;
        input integer microseconds;
        reg [63:0] product;
        begin
            product = CLK_HZ;
            product = product * microseconds;
            clocks_for_us = (product + 64'd999999) / 64'd1000000;
        end
    endfunction

    localparam integer POWER_CYCLES = clocks_for_us(50000);
    localparam integer SETUP_CYCLES = clocks_for_us(1);
    localparam integer HIGH_CYCLES = clocks_for_us(1);
    localparam integer WRITE_CYCLES = clocks_for_us(50);
    localparam integer CLEAR_CYCLES = clocks_for_us(2500);
    localparam integer WAKE1_CYCLES = clocks_for_us(5000);
    localparam integer WAKE2_CYCLES = clocks_for_us(150);

    localparam [2:0] POWER_UP = 3'd0, LOAD_INIT = 3'd1, LOAD_FRAME = 3'd2,
                     SETUP = 3'd3, PULSE = 3'd4, RECOVERY = 3'd5, IDLE = 3'd6;
    reg [2:0] state;
    reg [2:0] init_index;
    reg [5:0] frame_index;
    reg [31:0] wait_count;
    reg [31:0] after_write;
    reg init_done;
    reg frame_written;
    reg [127:0] frame1;
    reg [127:0] frame2;
    // Indices 1..16 and 18..33 are the line payloads. The low nibble wraps.
    wire [3:0] line1_index = frame_index[3:0] - 4'd1;
    wire [3:0] line2_index = frame_index[3:0] - 4'd2;
    wire [6:0] line1_bit = {~line1_index, 3'b000};
    wire [6:0] line2_bit = {~line2_index, 3'b000};

    assign lcd_rw = 1'b0;

    always @(posedge clk_sys) begin
        if (rst) begin
            state <= POWER_UP;
            init_index <= 3'd0;
            frame_index <= 6'd0;
            wait_count <= POWER_CYCLES - 1;
            after_write <= 32'd0;
            init_done <= 1'b0;
            frame_written <= 1'b0;
            frame1 <= 128'd0;
            frame2 <= 128'd0;
            lcd_data <= 8'd0;
            lcd_rs <= 1'b0;
            lcd_e <= 1'b0;
        end else begin
            case (state)
                POWER_UP: begin
                    if (wait_count == 0)
                        state <= LOAD_INIT;
                    else
                        wait_count <= wait_count - 32'd1;
                end
                LOAD_INIT: begin
                    lcd_rs <= 1'b0;
                    after_write <= WRITE_CYCLES;
                    case (init_index)
                        3'd0: begin
                            lcd_data <= 8'h30;
                            after_write <= WAKE1_CYCLES;
                        end
                        3'd1: begin
                            lcd_data <= 8'h30;
                            after_write <= WAKE2_CYCLES;
                        end
                        3'd2: lcd_data <= 8'h30;
                        3'd3: lcd_data <= 8'h38;
                        3'd4: lcd_data <= 8'h08;
                        3'd5: begin
                            lcd_data <= 8'h01;
                            after_write <= CLEAR_CYCLES;
                        end
                        3'd6: lcd_data <= 8'h06;
                        3'd7: lcd_data <= 8'h0c;
                    endcase
                    wait_count <= SETUP_CYCLES - 1;
                    state <= SETUP;
                end
                LOAD_FRAME: begin
                    lcd_rs <= 1'b0;
                    if (frame_index == 6'd0) begin
                        lcd_data <= 8'h80;
                    end else if (frame_index == 6'd17) begin
                        lcd_data <= 8'hc0;
                    end else begin
                        lcd_rs <= 1'b1;
                        if (frame_index < 6'd17)
                            lcd_data <= frame1[line1_bit +: 8];
                        else
                            lcd_data <= frame2[line2_bit +: 8];
                    end
                    after_write <= WRITE_CYCLES;
                    wait_count <= SETUP_CYCLES - 1;
                    state <= SETUP;
                end
                SETUP: begin
                    if (wait_count == 0) begin
                        lcd_e <= 1'b1;
                        wait_count <= HIGH_CYCLES - 1;
                        state <= PULSE;
                    end else begin
                        wait_count <= wait_count - 32'd1;
                    end
                end
                PULSE: begin
                    if (wait_count == 0) begin
                        lcd_e <= 1'b0;
                        wait_count <= after_write - 32'd1;
                        state <= RECOVERY;
                    end else begin
                        wait_count <= wait_count - 32'd1;
                    end
                end
                RECOVERY: begin
                    if (wait_count != 0) begin
                        wait_count <= wait_count - 32'd1;
                    end else if (!init_done) begin
                        if (init_index == 3'd7) begin
                            init_done <= 1'b1;
                            state <= IDLE;
                        end else begin
                            init_index <= init_index + 3'd1;
                            state <= LOAD_INIT;
                        end
                    end else if (frame_index == 6'd33) begin
                        frame_written <= 1'b1;
                        state <= IDLE;
                    end else begin
                        frame_index <= frame_index + 6'd1;
                        state <= LOAD_FRAME;
                    end
                end
                IDLE: begin
                    if (!frame_written || line1 != frame1 || line2 != frame2) begin
                        frame1 <= line1;
                        frame2 <= line2;
                        frame_index <= 6'd0;
                        state <= LOAD_FRAME;
                    end
                end
                default: state <= POWER_UP;
            endcase
        end
    end
endmodule
