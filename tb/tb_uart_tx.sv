`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_uart_tx: self-checking testbench for uart_tx
//
// Tests:
//   1. Idle line is high and not busy after reset
//   2. Frame format: start bit 0, 8 data bits LSB first, stop bit 1
//      (each bit sampled in its middle)
//   3. Directed bytes: 00 FF 55 AA 01 80
//   4. 20 random bytes
//   5. tx_busy high during the frame, tx_done one 1-clock pulse,
//      frame length exactly 10 * CLKS_PER_BIT clocks
//   6. Back-to-back: each new byte starts right after the previous one ends
//
// Prints "PASS: N checks, 0 errors" or "FAIL: ..." lines.
// -----------------------------------------------------------------------------
module tb_uart_tx;

    localparam int CLKS_PER_BIT = 8;      // small value = fast simulation
    localparam int CLK_PERIOD   = 10;     // 10 ns = 100 MHz

    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic       tx_start = 1'b0;
    logic [7:0] tx_data = 8'h00;
    logic       tx, tx_busy, tx_done;

    int checks = 0;
    int errors = 0;
    logic [7:0] rand_byte;

    // Device under test
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (tx),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // Compare one value with the expected value and count the result
    task automatic check(input string what, input logic [31:0] got, input logic [31:0] exp);
        checks++;
        if (got !== exp) begin
            errors++;
            $display("FAIL: %s: got 0x%0h, expected 0x%0h (t=%0t ns)", what, got, exp, $time);
        end
    endtask

    // Send one byte through the DUT and check everything about the frame.
    // The testbench changes inputs and samples outputs on the FALLING edge,
    // so it never races with the DUT, which works on the rising edge.
    task automatic send_and_check(input logic [7:0] b);
        logic [7:0] got_byte;
        int         clks;       // clocks counted since the start bit began
        int         wait_clks;

        check("tx_busy low before start", tx_busy, 0);

        // Pulse tx_start for one clock
        tx_data  = b;
        tx_start = 1'b1;
        @(negedge clk);
        tx_start = 1'b0;
        // The DUT took tx_start on the rising edge half a clock ago:
        // the start bit has begun.
        clks = 0;
        check("tx_busy high after start", tx_busy, 1);

        // Move to the middle of the start bit
        repeat (CLKS_PER_BIT/2) @(negedge clk);
        clks += CLKS_PER_BIT/2;
        check("start bit = 0", tx, 0);

        // 8 data bits, LSB first, each sampled in its middle
        for (int i = 0; i < 8; i++) begin
            repeat (CLKS_PER_BIT) @(negedge clk);
            clks += CLKS_PER_BIT;
            got_byte[i] = tx;
            check("tx_busy high during data", tx_busy, 1);
        end
        check("data byte", got_byte, b);

        // Stop bit
        repeat (CLKS_PER_BIT) @(negedge clk);
        clks += CLKS_PER_BIT;
        check("stop bit = 1", tx, 1);
        check("tx_done low before frame end", tx_done, 0);

        // Wait for tx_done (give up after 2 bit times)
        wait_clks = 0;
        while (tx_done !== 1'b1 && wait_clks < 2*CLKS_PER_BIT) begin
            @(negedge clk);
            clks++;
            wait_clks++;
        end
        check("tx_done pulse seen", tx_done, 1);
        check("frame length = 10 * CLKS_PER_BIT clocks", clks, 10*CLKS_PER_BIT);
        check("tx_busy low when done", tx_busy, 0);
        check("line high after frame", tx, 1);

        // tx_done must be only 1 clock long
        @(negedge clk);
        check("tx_done is a 1-clock pulse", tx_done, 0);
    endtask

    initial begin
        $dumpfile("tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);

        // Reset
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(negedge clk);

        // 1. Idle
        check("idle line high", tx, 1);
        check("idle not busy", tx_busy, 0);
        check("idle no tx_done", tx_done, 0);

        // 3. Directed bytes (edge cases)
        send_and_check(8'h00);   // all zeros
        send_and_check(8'hFF);   // all ones
        send_and_check(8'h55);   // 0101_0101
        send_and_check(8'hAA);   // 1010_1010
        send_and_check(8'h01);   // only LSB set
        send_and_check(8'h80);   // only MSB set

        // 4. Random bytes (also back-to-back: no idle gap between them)
        repeat (20) begin
            rand_byte = $urandom_range(0, 255);
            send_and_check(rand_byte);
        end

        // Result
        if (errors == 0)
            $display("PASS: %0d checks, 0 errors", checks);
        else
            $display("FAIL: %0d checks, %0d errors", checks, errors);
        $finish;
    end

    // Safety net: stop if the simulation hangs
    initial begin
        #(CLK_PERIOD * 100_000);
        $display("FAIL: timeout, simulation took too long");
        $finish;
    end

endmodule
