`ifndef BASEBALL_DEFS_VH
`define BASEBALL_DEFS_VH

// Bus layouts (MSB to LSB)
// pitch_ctrl: [3] start, [2] stop, [1:0] pitch type
// pitch_bus:  [7] active, [6] end on this edge, [5:4] type, [3:0] position
// runner_req: [5:3] current bases, [2:0] advance type
// runner_res: [5:3] next bases, [2:0] runs scored
// scores:     [15:8] P1, [7:0] P2
// lcd_state:  [12] done, [11:10] outcome, [9] bottom, [8:7] balls,
//             [6:5] strikes, [4:3] outs, [2:0] recent result
// For bases, bit 0 is first, bit 1 second, and bit 2 third.

`define PITCH_FAST  2'd0
`define PITCH_CURVE 2'd1
`define PITCH_BALL  2'd2

`define RES_NONE           3'd0
`define RES_SWING_STRIKE   3'd1
`define RES_LOOKING_STRIKE 3'd2
`define RES_BALL           3'd3
`define RES_HBP            3'd4
`define RES_SINGLE         3'd5
`define RES_DOUBLE         3'd6
`define RES_HOMER          3'd7

`define RUN_NONE   3'd0
`define RUN_FORCE  3'd1
`define RUN_SINGLE 3'd2
`define RUN_DOUBLE 3'd3
`define RUN_HOMER  3'd4

`define FX_NONE  2'd0
`define FX_PREP  2'd1
`define FX_HOMER 2'd2

`define OUTCOME_PLAY 2'd0
`define OUTCOME_P1   2'd1
`define OUTCOME_P2   2'd2
`define OUTCOME_DRAW 2'd3

`endif
