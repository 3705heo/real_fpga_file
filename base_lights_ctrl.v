`timescale 1ns/1ps

module base_lights_ctrl (
    input  wire [2:0] bases,
    output wire [2:0] base_lights
);
    // Logical bits 0, 1 and 2 are first, second and third base respectively.
    assign base_lights = bases;
endmodule
