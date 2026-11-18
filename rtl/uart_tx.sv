`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// uart_tx: UART transmitter, 8N1 (1 start bit, 8 data bits LSB first,
//          no parity, 1 stop bit).
//
// One frame takes exactly 10 * CLKS_PER_BIT clock cycles.
// CLKS_PER_BIT = clock frequency / baud rate
//   e.g. 100 MHz / 115200 baud = 868
//
// Usage: put a byte on tx_data and pulse tx_start for one clock while
//        tx_busy = 0. tx_done pulses high for one clock when the stop bit ends.
// -----------------------------------------------------------------------------
module uart_tx #(
    parameter int CLKS_PER_BIT = 868
) (
    input  logic       clk,
    input  logic       rst_n,      // active-low reset
    input  logic       tx_start,   // 1-clock pulse: start sending tx_data
    input  logic [7:0] tx_data,    // byte to send
    output logic       tx,         // serial output line (idle = 1)
    output logic       tx_busy,    // 1 while a frame is being sent
    output logic       tx_done     // 1-clock pulse at the end of the frame
);

    // The 4 states of the transmitter
    typedef enum logic [1:0] {
        IDLE,   // line high, waiting for tx_start
        START,  // sending the start bit (0)
        DATA,   // sending the 8 data bits, LSB first
        STOP    // sending the stop bit (1)
    } state_t;

    state_t state;

    // Counts clocks inside one bit: 0 .. CLKS_PER_BIT-1
    localparam int CNT_W = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    logic [CNT_W-1:0] clk_cnt;

    logic [2:0] bit_idx;  // which data bit is on the line: 0 .. 7
    logic [7:0] shreg;    // copy of the byte; shifted right, so bit 0 is next

    // "This bit has lasted CLKS_PER_BIT clocks, move on"
    logic bit_end;
    assign bit_end = (clk_cnt == CLKS_PER_BIT - 1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            clk_cnt <= '0;
            bit_idx <= '0;
            shreg   <= '0;
            tx      <= 1'b1;          // idle line is HIGH
            tx_done <= 1'b0;
        end else begin
            tx_done <= 1'b0;          // default: tx_done is a 1-clock pulse

            case (state)
                IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= '0;
                    if (tx_start) begin
                        shreg <= tx_data;   // latch the byte now
                        tx    <= 1'b0;      // start bit
                        state <= START;
                    end
                end

                START: begin
                    if (bit_end) begin
                        clk_cnt <= '0;
                        bit_idx <= '0;
                        tx      <= shreg[0];        // first data bit (LSB)
                        shreg   <= shreg >> 1;
                        state   <= DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DATA: begin
                    if (bit_end) begin
                        clk_cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            tx    <= 1'b1;          // stop bit
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                            tx      <= shreg[0];    // next data bit
                            shreg   <= shreg >> 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STOP: begin
                    if (bit_end) begin
                        clk_cnt <= '0;
                        tx_done <= 1'b1;            // frame finished
                        state   <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign tx_busy = (state != IDLE);

endmodule
