# Asynchronous FIFO Verilog RTL

An 8-bit asynchronous FIFO with an 8-entry depth, designed for transferring data between two independent clock domains.

## Overview

This project implements an asynchronous FIFO using separate write and read clock domains.

The FIFO allows data to be written using `wr_clk` and read using `rd_clk`, where the two clocks are independent and have different frequencies.

The design includes:

- 8-bit data width
- 8-entry FIFO depth
- Independent write and read clock domains
- Binary write and read pointers
- Gray-code pointer conversion
- Two-stage clock-domain synchronization
- Full and empty detection
- Registered read data
- Simulation-based verification with a scoreboard

## Architecture

```text
                 Write Clock Domain
                       wr_clk
                         │
                         ▼
                    Write Logic
                         │
                  Binary Pointer
                         │
                    Gray Pointer
                         │
                         ▼
                  2-FF Synchronizer
                         │
                         │
                         ▼
                    Read Domain
                         
              ┌───────────────────┐
              │    FIFO Memory    │
              │    8 × 8 bits     │
              └───────────────────┘
                         ▲
                         │
                    Read Logic
                         ▲
                  Binary Pointer
                         ▲
                    Gray Pointer
                         │
                  2-FF Synchronizer
                         │
                         │
                         ▼
                 Write Clock Domain
