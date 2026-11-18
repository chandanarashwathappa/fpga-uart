`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_uart_rx: self-checking testbench for uart_rx
//
// The testbench plays the role of a UART transmitter: it drives the rx line
// with exact 8N1 timing and checks what the receiver outputs.
//
// Tests:
//   1. Idle line: no output
//   2. Directed bytes: 00 FF 55 AA 01 80
//   3. 50 random bytes, sent back-to-back (no gap between frames)
//   4. Error injection: stop bit forced to 0 -> frame_err, no rx_valid
//      then a normal byte must still be received (recovery)
//   5. Glitch test: short low pulses on the idle line must not start a byte
//
// rx_valid and frame_err are counted on every clock, so a pulse that is
// too long, missing or extra is caught.
//
// Prints "PASS: N checks, 0 errors" or "FAIL: ..." lines.
// -----------------------------------------------------------------------------
module tb_uart_rx;

    localparam int CLKS_PER_BIT = 16;
    localparam int CLK_PERIOD   = 10;     // 10 ns = 100 MHz

    logic       clk   = 1'b0;
    logic       rst_n = 1'b0;
    logic       rx    = 1'b1;             // idle line is high
    logic [7:0] rx_data;
    logic       rx_valid, frame_err;

    int checks = 0;
    int errors = 0;
    logic [7:0] rand_byte;

    // Device under test
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .rx        (rx),
        .rx_data   (rx_data),
        .rx_valid  (rx_valid),
        .frame_err (frame_err)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Count every output pulse ------------------------------------------
    int         valid_count = 0;
    int         err_count   = 0;
    logic [7:0] last_data   = 8'h00;

    always @(negedge clk) begin
        if (rx_valid === 1'b1) begin
            valid_count++;
            last_data = rx_data;
        end
        if (frame_err === 1'b1)
            err_count++;
    end

    // ---- Helpers ------------------------------------------------------------
    task automatic check(input string what, input logic [31:0] got, input logic [31:0] exp);
        checks++;
        if (got !== exp) begin
            errors++;
            $display("FAIL: %s: got 0x%0h, expected 0x%0h (t=%0t ns)", what, got, exp, $time);
        end
    endtask

    // Drive one 8N1 frame on rx. stop_bit = 0 makes a broken frame.
    // Changes rx on the falling edge of clk, like an outside device would
    // (not in step with the DUT's rising edge).
    task automatic drive_frame(input logic [7:0] b, input logic stop_bit);
        rx = 1'b0;                                   // start bit
        repeat (CLKS_PER_BIT) @(negedge clk);
        for (int i = 0; i < 8; i++) begin            // data, LSB first
            rx = b[i];
            repeat (CLKS_PER_BIT) @(negedge clk);
        end
        rx = stop_bit;                               // stop bit
        repeat (CLKS_PER_BIT) @(negedge clk);
        rx = 1'b1;                                   // back to idle
    endtask

    // Send a good frame and check that exactly one byte came out, correctly
    task automatic send_and_check(input logic [7:0] b);
        int v0, e0;
        v0 = valid_count;
        e0 = err_count;
        drive_frame(b, 1'b1);
        check("one rx_valid per byte", valid_count, v0 + 1);
        check("rx_data matches sent byte", last_data, b);
        check("no frame_err on good byte", err_count, e0);
    endtask

    // Wait some idle time and check that nothing came out
    task automatic expect_nothing(input string what, input int clks);
        int v0, e0;
        v0 = valid_count;
        e0 = err_count;
        repeat (clks) @(negedge clk);
        if (valid_count != v0 || err_count != e0)
            $display("FAIL: unexpected output during: %s", what);
        check("no rx_valid expected", valid_count, v0);
        check("no frame_err expected", err_count, e0);
    endtask

    // ---- Test sequence ------------------------------------------------------
    initial begin
        int v0, e0;

        $dumpfile("tb_uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);

        // Reset
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(negedge clk);

        // 1. Idle line
        expect_nothing("idle line", 3 * CLKS_PER_BIT);

        // 2. Directed bytes (edge cases)
        send_and_check(8'h00);   // all zeros
        send_and_check(8'hFF);   // all ones
        send_and_check(8'h55);   // 0101_0101
        send_and_check(8'hAA);   // 1010_1010
        send_and_check(8'h01);   // only LSB set
        send_and_check(8'h80);   // only MSB set

        // 3. Random bytes, back-to-back
        repeat (50) begin
            rand_byte = $urandom_range(0, 255);
            send_and_check(rand_byte);
        end

        // 4. Error injection: stop bit = 0
        repeat (2 * CLKS_PER_BIT) @(negedge clk);
        v0 = valid_count;
        e0 = err_count;
        drive_frame(8'hA5, 1'b0);
        check("frame_err on bad stop bit", err_count, e0 + 1);
        check("no rx_valid on bad stop bit", valid_count, v0);
        repeat (2 * CLKS_PER_BIT) @(negedge clk);    // line idle again
        send_and_check(8'h3C);                       // receiver recovers

        // 5. Glitch tests: low pulses shorter than half a bit
        repeat (2 * CLKS_PER_BIT) @(negedge clk);
        rx = 1'b0;                                   // 1-clock glitch
        @(negedge clk);
        rx = 1'b1;
        expect_nothing("1-clock glitch", 3 * CLKS_PER_BIT);

        rx = 1'b0;                                   // quarter-bit glitch
        repeat (CLKS_PER_BIT / 4) @(negedge clk);
        rx = 1'b1;
        expect_nothing("quarter-bit glitch", 3 * CLKS_PER_BIT);

        send_and_check(8'hC3);                       // still works after glitches

        // Result
        if (errors == 0)
            $display("PASS: %0d checks, 0 errors", checks);
        else
            $display("FAIL: %0d checks, %0d errors", checks, errors);
        $finish;
    end

    // Safety net: stop if the simulation hangs
    initial begin
        #(CLK_PERIOD * 200_000);
        $display("FAIL: timeout, simulation took too long");
        $finish;
    end

endmodule
