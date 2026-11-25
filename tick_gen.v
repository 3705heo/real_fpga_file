`timescale 1ns/1ps

module tick_gen #(
    parameter integer CLK_HZ = 50_000_000
) (
    input wire clk_sys,
    input wire rst,
    output wire tick_ms
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

    // Phase accumulation keeps the average at 1000 ticks per second even
    // when CLK_HZ is not a multiple of 1000. CLK_HZ must be at least 1000.
    localparam integer PHASE_WIDTH = count_width(CLK_HZ - 1);
    localparam [PHASE_WIDTH-1:0] WRAP_BOUNDARY = CLK_HZ - 1000;
    reg [PHASE_WIDTH-1:0] phase = {PHASE_WIDTH{1'b0}};

    assign tick_ms = !rst && (phase >= WRAP_BOUNDARY);

    always @(posedge clk_sys) begin
        if (rst)
            phase <= {PHASE_WIDTH{1'b0}};
        else if (tick_ms)
            phase <= phase - WRAP_BOUNDARY;
        else
            phase <= phase + 1000;
    end
endmodule
