// =====================================================================
// FINAL TESTBENCH
// Configurable 4-Qubit Quantum-Inspired Image Processing Accelerator
// File: qip_accelerator_tb.v
// Verilog-2001 | Xilinx Vivado 2025.2
// =====================================================================

`timescale 1ns / 1ps

module qip_accelerator_tb;

    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst;
    reg start;

    reg [7:0] pix0;
    reg [7:0] pix1;
    reg [7:0] pix2;
    reg [7:0] pix3;

    reg [1:0] mode;

    wire busy;
    wire done;
    wire [7:0] result_pixel;

    integer test_num;
    integer pass_count;
    integer fail_count;
    integer timeout_count;

    reg [7:0] mode_result [0:3];

    reg [7:0] uniform_edge;
    reg [7:0] vertical_edge;
    reg [7:0] horizontal_edge;
    reg [7:0] diagonal_edge;
    reg [7:0] gradient_edge;

    // ================================================================
    // DUT
    // ================================================================

    qip_accelerator #(
        .WIDTH(16),
        .FRAC(12)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),

        .pix0(pix0),
        .pix1(pix1),
        .pix2(pix2),
        .pix3(pix3),

        .mode(mode),

        .busy(busy),
        .done(done),
        .result_pixel(result_pixel)
    );

    // ================================================================
    // 100 MHz clock
    // ================================================================

    initial begin
        clk = 1'b0;
    end

    always #(CLK_PERIOD/2) clk = ~clk;

    // ================================================================
    // Run one test
    // ================================================================

    task run_test;

        input [7:0] t_pix0;
        input [7:0] t_pix1;
        input [7:0] t_pix2;
        input [7:0] t_pix3;

        input [1:0] t_mode;

        output [7:0] t_result;

        begin

            // Wait until DUT is idle
            while (busy === 1'b1)
                @(negedge clk);

            // Apply inputs away from active edge
            @(negedge clk);

            pix0 = t_pix0;
            pix1 = t_pix1;
            pix2 = t_pix2;
            pix3 = t_pix3;

            mode  = t_mode;
            start = 1'b1;

            // One-cycle start pulse
            @(negedge clk);
            start = 1'b0;

            timeout_count = 0;

            // Wait for operation to complete
            while ((done !== 1'b1) &&
                   (timeout_count < 100)) begin

                @(negedge clk);
                timeout_count = timeout_count + 1;

                if ((busy === 1'b1) &&
                    (done === 1'b1)) begin

                    $display(
                        "FAIL: busy and done asserted together"
                    );

                    fail_count = fail_count + 1;

                end

            end

            if (timeout_count >= 100) begin

                $display(
                    "FAIL: DUT timeout | Mode=%b",
                    t_mode
                );

                fail_count = fail_count + 1;
                t_result = 8'd0;

            end
            else begin

                t_result = result_pixel;
                test_num = test_num + 1;

                $display(
                    "---------------------------------------------------"
                );

                $display(
                    "Test #%0d | Mode=%b | Pixels=%0d,%0d,%0d,%0d",
                    test_num,
                    t_mode,
                    t_pix0,
                    t_pix1,
                    t_pix2,
                    t_pix3
                );

                $display(
                    "Result=%0d | amp0=%0d amp1=%0d amp2=%0d amp3=%0d",
                    result_pixel,
                    dut.amp[0],
                    dut.amp[1],
                    dut.amp[2],
                    dut.amp[3]
                );

                pass_count = pass_count + 1;

            end

            // Allow FSM to return to IDLE
            @(negedge clk);
            @(negedge clk);

        end

    endtask

    // ================================================================
    // Check whether modes produce different behavior
    // ================================================================

    task check_mode_difference;

        input [7:0] r0;
        input [7:0] r1;
        input [7:0] r2;
        input [7:0] r3;

        begin

            if ((r0 == r1) &&
                (r1 == r2) &&
                (r2 == r3)) begin

                $display(
                    "CHECK FAIL: All modes returned %0d",
                    r0
                );

                fail_count = fail_count + 1;

            end
            else begin

                $display(
                    "CHECK PASS: Mode outputs = %0d, %0d, %0d, %0d",
                    r0, r1, r2, r3
                );

                pass_count = pass_count + 1;

            end

        end

    endtask

    // ================================================================
    // Main stimulus
    // ================================================================

    initial begin

        rst   = 1'b1;
        start = 1'b0;

        pix0 = 8'd0;
        pix1 = 8'd0;
        pix2 = 8'd0;
        pix3 = 8'd0;

        mode = 2'b00;

        test_num      = 0;
        pass_count    = 0;
        fail_count    = 0;
        timeout_count = 0;

        uniform_edge    = 8'd0;
        vertical_edge   = 8'd0;
        horizontal_edge = 8'd0;
        diagonal_edge   = 8'd0;
        gradient_edge   = 8'd0;

        // Reset
        repeat (5)
            @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        repeat (2)
            @(posedge clk);

        // =============================================================
        // PATTERN 1: UNIFORM
        // =============================================================

        $display("");
        $display("========== UNIFORM PATTERN ==========");

        run_test(
            8'd100, 8'd100,
            8'd100, 8'd100,
            2'b00,
            mode_result[0]
        );

        uniform_edge = mode_result[0];

        run_test(
            8'd100, 8'd100,
            8'd100, 8'd100,
            2'b01,
            mode_result[1]
        );

        run_test(
            8'd100, 8'd100,
            8'd100, 8'd100,
            2'b10,
            mode_result[2]
        );

        run_test(
            8'd100, 8'd100,
            8'd100, 8'd100,
            2'b11,
            mode_result[3]
        );

        check_mode_difference(
            mode_result[0],
            mode_result[1],
            mode_result[2],
            mode_result[3]
        );

        // =============================================================
        // PATTERN 2: VERTICAL EDGE
        // =============================================================

        $display("");
        $display("========== VERTICAL EDGE ==========");

        run_test(
            8'd0, 8'd255,
            8'd0, 8'd255,
            2'b00,
            mode_result[0]
        );

        vertical_edge = mode_result[0];

        run_test(
            8'd0, 8'd255,
            8'd0, 8'd255,
            2'b01,
            mode_result[1]
        );

        run_test(
            8'd0, 8'd255,
            8'd0, 8'd255,
            2'b10,
            mode_result[2]
        );

        run_test(
            8'd0, 8'd255,
            8'd0, 8'd255,
            2'b11,
            mode_result[3]
        );

        check_mode_difference(
            mode_result[0],
            mode_result[1],
            mode_result[2],
            mode_result[3]
        );

        // =============================================================
        // PATTERN 3: HORIZONTAL EDGE
        // =============================================================

        $display("");
        $display("========== HORIZONTAL EDGE ==========");

        run_test(
            8'd0, 8'd0,
            8'd255, 8'd255,
            2'b00,
            mode_result[0]
        );

        horizontal_edge = mode_result[0];

        run_test(
            8'd0, 8'd0,
            8'd255, 8'd255,
            2'b01,
            mode_result[1]
        );

        run_test(
            8'd0, 8'd0,
            8'd255, 8'd255,
            2'b10,
            mode_result[2]
        );

        run_test(
            8'd0, 8'd0,
            8'd255, 8'd255,
            2'b11,
            mode_result[3]
        );

        check_mode_difference(
            mode_result[0],
            mode_result[1],
            mode_result[2],
            mode_result[3]
        );

        // =============================================================
        // PATTERN 4: DIAGONAL EDGE
        // =============================================================

        $display("");
        $display("========== DIAGONAL PATTERN ==========");

        run_test(
            8'd255, 8'd0,
            8'd0, 8'd255,
            2'b00,
            mode_result[0]
        );

        diagonal_edge = mode_result[0];

        run_test(
            8'd255, 8'd0,
            8'd0, 8'd255,
            2'b01,
            mode_result[1]
        );

        run_test(
            8'd255, 8'd0,
            8'd0, 8'd255,
            2'b10,
            mode_result[2]
        );

        run_test(
            8'd255, 8'd0,
            8'd0, 8'd255,
            2'b11,
            mode_result[3]
        );

        check_mode_difference(
            mode_result[0],
            mode_result[1],
            mode_result[2],
            mode_result[3]
        );

        // =============================================================
        // PATTERN 5: GRADIENT
        // =============================================================

        $display("");
        $display("========== GRADIENT PATTERN ==========");

        run_test(
            8'd40, 8'd90,
            8'd140, 8'd190,
            2'b00,
            mode_result[0]
        );

        gradient_edge = mode_result[0];

        run_test(
            8'd40, 8'd90,
            8'd140, 8'd190,
            2'b01,
            mode_result[1]
        );

        run_test(
            8'd40, 8'd90,
            8'd140, 8'd190,
            2'b10,
            mode_result[2]
        );

        run_test(
            8'd40, 8'd90,
            8'd140, 8'd190,
            2'b11,
            mode_result[3]
        );

        check_mode_difference(
            mode_result[0],
            mode_result[1],
            mode_result[2],
            mode_result[3]
        );

        // =============================================================
        // EDGE RESPONSE CHECK
        // =============================================================

        $display("");
        $display("========== EDGE RESPONSE CHECK ==========");

        $display(
            "Uniform=%0d Vertical=%0d Horizontal=%0d Diagonal=%0d Gradient=%0d",
            uniform_edge,
            vertical_edge,
            horizontal_edge,
            diagonal_edge,
            gradient_edge
        );

        if ((vertical_edge > uniform_edge) &&
            (horizontal_edge > uniform_edge) &&
            (diagonal_edge > uniform_edge)) begin

            $display(
                "CHECK PASS: Strong edges exceed uniform response"
            );

            pass_count = pass_count + 1;

        end
        else begin

            $display(
                "CHECK FAIL: Edge response behavior incorrect"
            );

            fail_count = fail_count + 1;

        end

        // =============================================================
        // FINAL SUMMARY
        // =============================================================

        $display("");
        $display("===================================================");
        $display("FINAL SIMULATION SUMMARY");
        $display("===================================================");
        $display("Tests completed : %0d", test_num);
        $display("Checks passed   : %0d", pass_count);
        $display("Checks failed   : %0d", fail_count);

        if (fail_count == 0)
            $display("FINAL RESULT: ALL TESTS PASSED");
        else
            $display("FINAL RESULT: SOME TESTS FAILED");

        $display("===================================================");

        #20;
        $finish;

    end

    // ================================================================
    // Global timeout
    // ================================================================

    initial begin

        #500000;

        $display(
            "FATAL ERROR: GLOBAL SIMULATION TIMEOUT"
        );

        $finish;

    end

endmodule
