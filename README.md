# UART + SPI Communication Cores (SystemVerilog)

[![sim](https://github.com/chandanarashwathappa/fpga-uart/actions/workflows/sim.yml/badge.svg)](https://github.com/chandanarashwathappa/fpga-uart/actions/workflows/sim.yml)

Serial communication blocks for FPGA: a UART transmitter, a UART receiver and an
SPI master. Each block has a self-checking testbench that prints PASS or FAIL,
and GitHub Actions runs all of them on every push.

> Status: work in progress: UART TX, RX and loopback done. See [Progress](#progress).

## Architecture

```
                 ┌──────────────┐   tx line   ┌──────────────┐
 tx_data[7:0] ──►│   uart_tx    │────────────►│   uart_rx    │──► rx_data[7:0]
 tx_start     ──►│  (FSM, 4 st.)│             │ (FSM + mid-  │──► rx_valid
                 └──────────────┘             │  bit sample) │──► frame_err
                                              └──────────────┘
                 ┌──────────────┐  SCLK, MOSI, CS_n
 data_in[7:0] ──►│  spi_master  │────────────────────► SPI slave model (in testbench)
 start        ──►│ (mode 0–3)   │◄──────────────────── MISO
                 └──────────────┘
```

## Specification

| Module | Features | Parameters | Main signals |
|---|---|---|---|
| `uart_tx` | 8N1 frame, LSB first, busy/done flags | `CLKS_PER_BIT` | `tx_start`, `tx_data`, `tx`, `tx_busy`, `tx_done` |
| `uart_rx` | 2-FF input synchroniser, start-bit check, mid-bit sampling, framing-error flag | `CLKS_PER_BIT` | `rx`, `rx_data`, `rx_valid`, `frame_err` |
| `spi_master` | SPI modes 0–3 (CPOL/CPHA), full duplex, chip select, clock divider | `CLK_DIV`, `CPOL`, `CPHA` | `start`, `data_in`, `data_out`, `sclk`, `mosi`, `miso`, `cs_n`, `done` |

## Verification plan

| Test | What it checks |
|---|---|
| Directed bytes | 0x00, 0xFF, 0x55, 0xAA, 0x01, 0x80 |
| Random bytes | 20–100 random bytes, each compared automatically |
| Timing check | Each bit lasts exactly `CLKS_PER_BIT` clocks |
| Back-to-back | Bytes sent with no gap; busy/done behave correctly |
| Loopback | TX → RX, received byte = sent byte |
| Error injection | Stop bit forced to 0 → RX raises `frame_err` |
| Glitch test | A 1-clock low pulse on idle RX does not start a false byte |
| SPI all modes | Data matches for all 4 CPOL/CPHA combinations |

## Repository layout

```
rtl/      uart_tx.sv, uart_rx.sv, spi_master.sv
tb/       tb_uart_tx.sv, tb_uart_rx.sv, tb_loopback.sv, tb_spi.sv
docs/     block diagram, waveform screenshots, PASS logs
.github/  CI workflow (Icarus Verilog on Ubuntu)
```

## How to run

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/) and, for
waveforms, [GTKWave](https://gtkwave.sourceforge.net/).

```sh
make sim                 # run every testbench that exists
make test_uart_tx        # run one testbench
make wave TEST=uart_tx   # open its waveform in GTKWave
make clean
```

Testbench conventions (the Makefile and CI rely on them):

- the top module is `tb_<test>` (for example `tb_uart_tx`)
- a passing run prints a line starting with `PASS`, e.g. `PASS: 42 checks, 0 errors`
- any mismatch prints a line containing `FAIL`
- waveforms: `$dumpfile("tb_<test>.vcd"); $dumpvars(0, tb_<test>);`

## Results

| Testbench | Checks | Errors |
|---|---|---|
| `tb_uart_tx` | TBD | TBD |
| `tb_uart_rx` | TBD | TBD |
| `tb_loopback` | TBD | TBD |
| `tb_spi` | TBD | TBD |

Synthesis (Vivado, optional): TBD LUTs, TBD flip-flops.

## Progress

- [x] `uart_tx` + testbench
- [x] `uart_rx` + testbench + error injection
- [x] Loopback test + green CI
- [ ] `spi_master` (4 modes) + slave model + testbench
- [ ] Waveforms and results in `docs/`

## What I learned

_To be written._

## License

MIT
