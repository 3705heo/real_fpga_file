`timescale 1ns/1ps
`include "baseball_defs.vh"

module tb_runner_update;
    reg  [5:0] runner_req;
    wire [5:0] runner_res;
    integer checks;

    runner_update dut (.runner_req(runner_req), .runner_res(runner_res));

    task check_move;
        input [2:0] before_bases;
        input [2:0] move;
        input [2:0] after_bases;
        input [2:0] runs;
        begin
            runner_req = {before_bases, move};
            #1;
            if (runner_res !== {after_bases, runs})
                $fatal(1, "bases=%b move=%0d expected bases=%b runs=%0d got bases=%b runs=%0d",
                       before_bases, move, after_bases, runs, runner_res[5:3], runner_res[2:0]);
            checks = checks + 1;
        end
    endtask

    task check_row;
        input [2:0] before_bases;
        input [5:0] single_result;
        input [5:0] double_result;
        input [5:0] force_result;
        input [5:0] homer_result;
        begin
            check_move(before_bases, `RUN_SINGLE, single_result[5:3], single_result[2:0]);
            check_move(before_bases, `RUN_DOUBLE, double_result[5:3], double_result[2:0]);
            check_move(before_bases, `RUN_FORCE,  force_result[5:3],  force_result[2:0]);
            check_move(before_bases, `RUN_HOMER,  homer_result[5:3],  homer_result[2:0]);
            check_move(before_bases, `RUN_NONE, before_bases, 3'd0);
        end
    endtask

    initial begin
        checks = 0;
        // Each value is BBB_RRR, with bases ordered third, second, first.
        // Ball four and HBP both use the RUN_FORCE column.
        //          Before    Single     Double     Force      Homer
        check_row(3'b000,  6'b001_000, 6'b010_000, 6'b001_000, 6'b000_001);
        check_row(3'b001,  6'b011_000, 6'b110_000, 6'b011_000, 6'b000_010);
        check_row(3'b010,  6'b101_000, 6'b010_001, 6'b011_000, 6'b000_010);
        check_row(3'b011,  6'b111_000, 6'b110_001, 6'b111_000, 6'b000_011);
        check_row(3'b100,  6'b001_001, 6'b010_001, 6'b101_000, 6'b000_010);
        check_row(3'b101,  6'b011_001, 6'b110_001, 6'b111_000, 6'b000_011);
        check_row(3'b110,  6'b101_001, 6'b010_010, 6'b111_000, 6'b000_011);
        check_row(3'b111,  6'b111_001, 6'b110_010, 6'b111_001, 6'b000_100);
        check_move(3'b101, 3'd5, 3'b101, 3'd0);
        check_move(3'b010, 3'd6, 3'b010, 3'd0);
        check_move(3'b110, 3'd7, 3'b110, 3'd0);
        $display("PASS tb_runner_update (%0d checks)", checks);
        $finish;
    end
endmodule
