# Mini SoC Design and Layered SystemVerilog Verification

## Overview

This project implements a simplified memory-mapped Mini SoC in SystemVerilog along with a structured layered testbench.

The goal is to demonstrate:

- Register-based SoC architecture
- Inter-block communication
- Constrained random verification
- Layered testbench design (Generator → Driver → Monitor → Scoreboard)
- Cycle-accurate reference model checking

The focus is clarity, correctness, and methodology rather than protocol complexity.

---

# Design Architecture

## Memory Map

| Address | Register         | Description                         |
|----------|-----------------|-------------------------------------|
| 0x00     | Control Register| Bit[0] enables counter              |
| 0x04     | GPIO Register   | 4-bit memory-mapped output          |
| 0x08     | Counter Register| Increments when enabled             |
| 0x0C     | Status Register | Aggregated GPIO + Control status    |

---

## Internal Blocks

### 1. Control Register
- Written through memory-mapped interface
- Bit[0] controls counter enable

### 2. GPIO Peripheral
- 4-bit output register
- Writable and readable

### 3. Counter Peripheral
- Sequential logic
- Increments every clock when enabled

### 4. Status Register
- Combinational aggregation of internal state

---

# Verification Architecture

Layered SystemVerilog testbench:
Generator → Driver → DUT → Monitor → Scoreboard

## Components

### Transaction
- Constrained random generation
- Valid read/write combinations only
- Restricted to valid address map

### Generator
- Produces randomized transactions

### Driver
- Drives interface using clocking block
- Uses semaphore for bus control

### Monitor
- Passively observes read transactions

### Scoreboard
- Maintains cycle-accurate reference model
- Mirrors RTL behavior
- Checks expected vs actual data
- Correctly models nonblocking counter behavior

---

# Synchronization Mechanisms Used

- Mailbox (Generator → Driver)
- Mailbox (Monitor → Scoreboard)
- Semaphore (bus access control)
- Event (transaction completion signaling)
- Virtual Interface
- Clocking block

---

# Simulation Output

Simulation performed using Riviera-PRO (EDU Edition).

Example output:
 KERNEL: Read Addr=4 Data=0
 KERNEL: Read Addr=8 Data=0
 KERNEL: Read Addr=0 Data=0
 KERNEL: Read Addr=4 Data=0
 KERNEL: Read Addr=8 Data=0
 KERNEL: Read Addr=8 Data=0
 KERNEL: Read Addr=4 Data=f
 KERNEL: Read Addr=0 Data=c1429199
 KERNEL: Read Addr=4 Data=f
 KERNEL: Read Addr=4 Data=f
 KERNEL: Read Addr=0 Data=c1429199
 KERNEL: Read Addr=8 Data=6
 KERNEL: Read Addr=c Data=f8
 KERNEL: Read Addr=4 Data=f
 KERNEL: Read Addr=c Data=f8
 RUNTIME: Info: RUNTIME_0068 testbench.sv (309): $finish called.

 
No mismatches were reported during simulation.

---

# Key Technical Learnings

- Memory-mapped register design
- Address decoding
- Sequential vs combinational logic partitioning
- Constrained random stimulus generation
- Thread-safe communication using mailboxes
- Resource protection using semaphores
- Cycle-accurate scoreboard modeling
- Handling nonblocking assignment timing in reference models

---

# Tools Used

- SystemVerilog
- Riviera-PRO Simulator
- ModelSim-compatible simulation structure

---

# Project Structure
design.sv → Interface + Mini SoC RTL
testbench.sv → Layered Verification Environment
README.md → Documentation

