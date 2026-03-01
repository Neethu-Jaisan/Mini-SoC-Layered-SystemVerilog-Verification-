# Mini SoC – Layered SystemVerilog Verification

## Overview

This project implements and verifies a memory-mapped Mini SoC using a layered SystemVerilog testbench architecture (non-UVM).

The SoC includes:
- Control register
- GPIO register
- Timer block
- FIFO block

The verification environment uses a Generator–Driver–Monitor–Scoreboard architecture with constrained-random stimulus, cycle-accurate reference modeling, functional coverage, and assertions.

---

## Architecture

Address Map:

| Address | Function |
|---------|----------|
| 0x00    | Control Register |
| 0x04    | GPIO Register |
| 0x08    | Timer Register |
| 0x10    | FIFO Write |
| 0x14    | FIFO Read |

---

## Verification Features

- Constrained-random transaction generation
- Weighted address distribution
- Mailbox-based communication
- Semaphore-based bus control
- Event synchronization
- Cycle-accurate scoreboard model
- Mid-test reset validation
- Functional coverage collection
- Assertion-based protocol checking

---

## Tools Used

- SystemVerilog
- Riviera-PRO / ModelSim compatible
- Functional Coverage (covergroup)
- Immediate & Concurrent Assertions

---

## How to Run

```bash
vlib work
vlog -timescale 1ns/1ns rtl/*.sv tb/*.sv
vsim tb -c -do "run -all; exit"
