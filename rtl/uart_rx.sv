`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// uart_rx: UART receiver, 8N1 (1 start bit, 8 data bits LSB first,
//          no parity, 1 stop bit).
//
// - 2-flip-flop synchroniser on the rx input: rx comes from outside the FPGA
//   and is not synchronous to clk, so it can make a flip-flop go metastable.
//   Two flip-flops in a row give that time to settle before the logic uses it.
// - Start-bit check: after a falling edge the line is checked again in the
//   middle of the start bit. If it is high again, it was only a glitch.
// - Every bit is sampled in its middle, the point furthest from the edges,
//   so small baud-rate differences and slow edges do not matter.
// - Stop bit must be 1. If it is 0, frame_err pulses and rx_valid does not.
//
// rx_valid and frame_err are 1-clock pulses. rx_data holds the last good byte.
// CLKS_PER_BIT = clock frequency / baud rate (must be >= 2).
// -----------------------------------------------------------------------------
module uart_rx #(
    parameter int CLKS_PER_BIT = 868
) (
    input  logic       clk,
    input  logic       rst_n,      // active-low reset
    input  logic       rx,         // serial input line (idle = 1)
    output logic [7:0] rx_data,    // received byte
    output logic       rx_valid,   // 1-clock pulse: rx_data is a new good byte
    output logic       frame_err   // 1-clock pulse: stop bit was 0
);

    typedef enum logic [1:0] {
        IDLE,   // waiting for a falling edge (start bit)
        START,  // waiting until the middle of the start bit to confirm it
        DATA,   // sampling 8 data bits in their middles
        STOP    // sampling the stop bit
    } state_t;

    state_t state;

    localparam int CNT_W = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    localparam int HALF  = CLKS_PER_BIT / 2;

    logic [CNT_W-1:0] clk_cnt;
    logic [2:0]       bit_idx;
    logic [7:0]       shreg;

    // ---- 2-flip-flop synchroniser -------------------------------------------
    logic [1:0] sync;
    logic       rx_s;     // synchronised rx: safe to use
    logic       rx_prev;  // rx_s one clock ago, for falling-edge detection

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) sync <= 2'b11;              // line idles high
        else        sync <= {sync[0], rx};
    end
    assign rx_s = sync[1];

    logic bit_end, half_bit;
    assign bit_end  = (clk_cnt == CLKS_PER_BIT - 1);
    assign half_bit = (clk_cnt == HALF - 1);

    // ---- Receiver state machine ---------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            clk_cnt   <= '0;
            bit_idx   <= '0;
            shreg     <= '0;
            rx_prev   <= 1'b1;
            rx_data   <= '0;
            rx_valid  <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            rx_prev   <= rx_s;
            rx_valid  <= 1'b0;        // defaults: both are 1-clock pulses
            frame_err <= 1'b0;

            case (state)
                IDLE: begin
                    clk_cnt <= '0;
                    // A start bit begins with a 1 -> 0 edge. Waiting for an
                    // edge (not just a 0) means a line stuck low after a
                    // framing error does not start new bytes.
                    if (rx_prev && !rx_s)
                        state <= START;
                end

                START: begin
                    if (half_bit) begin
                        clk_cnt <= '0;
                        if (!rx_s) begin       // still low: real start bit
                            bit_idx <= '0;
                            state   <= DATA;
                        end else begin         // back high: glitch, ignore
                            state   <= IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DATA: begin
                    // We are now in the middle of a bit every CLKS_PER_BIT clocks
                    if (bit_end) begin
                        clk_cnt <= '0;
                        shreg   <= {rx_s, shreg[7:1]};   // LSB first: shift in from the top
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STOP: begin
                    if (bit_end) begin
                        clk_cnt <= '0;
                        state   <= IDLE;
                        if (rx_s) begin        // good stop bit
                            rx_data  <= shreg;
                            rx_valid <= 1'b1;
                        end else begin         // stop bit is 0: framing error
                            frame_err <= 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
