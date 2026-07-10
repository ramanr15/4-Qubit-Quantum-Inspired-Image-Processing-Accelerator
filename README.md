# 4-Qubit Quantum-Inspired Image Processing Accelerator

A configurable FPGA architecture for quantum-inspired image processing, designed in Verilog and verified using AMD Vivado 2025.2.

The accelerator processes a 2x2 image patch using a classical 16-amplitude representation corresponding to a 4-qubit state vector. It supports four configurable processing modes:

- Edge Detection
- Sharpening
- Smoothing
- Feature Extraction

The design uses fixed-point arithmetic, quantum-inspired gate transformations, CNOT-style basis-state permutations, multi-cycle measurement, and hardware-efficient output scaling.

> **Note:** This project does not implement physical quantum hardware or real qubits. It is a classical FPGA architecture that mathematically emulates selected 4-qubit state-vector operations.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Processing Stages](#processing-stages)
- [Finite State Machine](#finite-state-machine)
- [Verification](#verification)
- [Results](#results)
- [FPGA Synthesis Results](#fpga-synthesis-results)
- [Timing Results](#timing-results)
- [Project Files](#project-files)
- [How to Run](#how-to-run)
- [Technologies Used](#technologies-used)
- [Key Features](#key-features)
- [Limitations](#limitations)
- [Future Work](#future-work)
- [Author](#author)
- [License](#license)

---

## Project Overview

The accelerator accepts four 8-bit pixels representing a 2x2 image patch:

```text
pix0   pix1
pix2   pix3
```

A 2-bit mode input selects the processing operation:

| Mode | Operation |
|------|-----------|
| `00` | Edge Detection |
| `01` | Sharpening |
| `10` | Smoothing |
| `11` | Feature Extraction |

The four input pixels are encoded into an internal 16-amplitude state representation. A 4-qubit system mathematically contains `2^4 = 16` basis states, so the accelerator maintains 16 signed fixed-point amplitudes internally (`amp[0]` ... `amp[15]`), stored using 16-bit Q4.12 fixed-point representation.

---

## Architecture

```text
Four 8-bit Pixels + Processing Mode
                  |
                  v
          Input Registration
                  |
                  v
      16-Amplitude State Encoding
                  |
                  v
     Quantum-Inspired Gate Stage 1
                  |
                  v
     Quantum-Inspired Gate Stage 2
                  |
                  v
      Mode-Specific Gate Stage 3
                  |
                  v
       CNOT-Style State Permutation
                  |
                  v
       Multi-Cycle Energy Measurement
                  |
                  v
        Divider-Free Output Scaling
                  |
                  v
          8-bit result_pixel
```

---

## Processing Stages

### 1. Input Registration

The accelerator receives four 8-bit pixels, a 2-bit processing mode, and a `start` signal. The pixels and mode are stored internally when processing begins, and the `busy` signal remains high while the accelerator is operating.

### 2. State Encoding

The four pixels are encoded into the first four positions of the internal 16-amplitude state vector:

```text
Pixel 0 -> amp[0]
Pixel 1 -> amp[1]
Pixel 2 -> amp[2]
Pixel 3 -> amp[3]
```

The remaining amplitudes are initialized to zero.

### 3. Quantum-Inspired Gate Stage 1

Performs pairwise amplitude mixing. Hadamard-like operations generate sum-related and difference-related components, allowing the accelerator to respond to variations between neighboring pixel values:

```text
Similar pixels   -> small difference response
Different pixels -> large difference response
```

### 4. Quantum-Inspired Gate Stage 2

Mixes additional amplitude groups, allowing the state representation to capture different spatial relationships within the 2x2 image patch.

### 5. Mode-Specific Gate Stage 3

The selected processing mode controls the final transformation stage:

| Mode | Behavior |
|------|----------|
| Edge Detection | Emphasizes difference-sensitive amplitude components |
| Sharpening | Emphasizes detail-related and high-frequency state energy |
| Smoothing | Emphasizes smoother and low-frequency state components |
| Feature Extraction | Generates a weighted transformed-state energy signature |

### 6. CNOT-Style State Permutation

A CNOT-inspired basis-state permutation rearranges selected amplitudes according to control-target bit relationships. Different modes use different control and target relationships.

### 7. Multi-Cycle Measurement

The transformed amplitudes are measured sequentially, one per clock cycle:

```text
Energy = Amplitude x Amplitude

Cycle 1  -> amp[0]^2
Cycle 2  -> amp[1]^2
Cycle 3  -> amp[2]^2
...
Cycle 16 -> amp[15]^2
```

The required energy components are accumulated according to the selected processing mode.

### 8. Output Scaling

The accumulated energy is converted into an 8-bit result using hardware-efficient shift-based scaling instead of variable division. The result is provided through `result_pixel[7:0]`. When processing completes: `done = 1`, `busy = 0`.

---

## Finite State Machine

```text
IDLE -> INIT -> GATE1 -> GATE2 -> GATE3 -> CNOT -> MEAS_INIT -> MEAS_RUN -> SCALE -> OUTPUT -> DONE
```

The `MEAS_RUN` state processes all 16 amplitudes sequentially.

---

## Verification

The design was verified using a self-checking Verilog testbench in Vivado 2025.2. Five image patterns were tested across all four processing modes (`5 patterns x 4 modes = 20 tests`):

1. Uniform region
2. Vertical edge
3. Horizontal edge
4. Diagonal edge
5. Gradient

**Final Simulation Summary**

```text
Tests completed : 20
Checks passed   : 26
Checks failed   : 0

FINAL RESULT: ALL TESTS PASSED
```

---

## Results

### Edge Detection Results

| Input Pattern | Edge Response |
|---------------|--------------:|
| Uniform | 0 |
| Gradient | 3 |
| Vertical Edge | 15 |
| Horizontal Edge | 15 |
| Diagonal Edge | 15 |

```text
No pixel variation -> No edge response
Gradual variation  -> Small response
Strong edge        -> High response
```

### Four-Mode Example

For a vertical-edge input:

```text
0   255
0   255
```

| Mode | Result |
|------|-------:|
| Edge Detection | 15 |
| Sharpening | 18 |
| Smoothing | 10 |
| Feature Extraction | 9 |

This confirms that the four processing modes produce distinct responses for the same input pattern.

---

## FPGA Synthesis Results

Synthesized for an AMD Xilinx Artix-7 target.

| Metric | Final Result |
|--------|-------------:|
| Target Frequency | 50 MHz |
| LUTs | 3,697 |
| Registers | 452 |
| DSP Blocks | 131 |
| Bonded I/O | 47 |
| Estimated On-Chip Power | 0.189 W |

---

## Timing Results

The design achieved timing closure at 50 MHz.

```text
Worst Negative Slack (WNS) : +2.676 ns
Total Negative Slack (TNS) : 0.000 ns
Failing Endpoints          : 0
```

All user-specified timing constraints were met.

---

## Project Files

```text
4-Qubit-Quantum-Inspired-Image-Processing-Accelerator/
|
|-- rtl/
|   |-- qip_accelerator.v
|
|-- simulation/
|   |-- qip_accelerator_tb.v
|
|-- constraints/
|   |-- qip_accelerator.xdc
|
|-- results/
|   |-- waveform.png
|   |-- simulation_results.png
|   |-- timing_summary.png
|   |-- utilization.png
|   |-- power.png
|
|-- README.md
|-- LICENSE
|-- .gitignore
```

---

## How to Run

### Requirements

- AMD Vivado 2025.2
- XSim Simulator
- Artix-7 FPGA target

### Simulation

1. Create a new RTL project in Vivado.
2. Add `rtl/qip_accelerator.v` as a Design Source.
3. Add `simulation/qip_accelerator_tb.v` as a Simulation Source.
4. Add `constraints/qip_accelerator.xdc` as a Constraint Source.
5. Set `qip_accelerator_tb` as the simulation top.
6. Launch Behavioral Simulation.
7. Run:

   ```tcl
   run all
   ```

Expected final result:

```text
Tests completed : 20
Checks passed   : 26
Checks failed   : 0
FINAL RESULT: ALL TESTS PASSED
```

### Synthesis

1. Set `qip_accelerator` as the Design Top.
2. Run Synthesis.
3. Open the synthesized design.
4. Check the Timing Summary, Utilization, and Power Report.

The design uses a 20 ns clock constraint corresponding to 50 MHz.

---

## Technologies Used

- Verilog HDL
- AMD Vivado 2025.2
- XSim
- Artix-7 FPGA architecture
- Q4.12 fixed-point arithmetic
- Finite State Machine design
- Multi-cycle datapath architecture
- Quantum-inspired state-vector processing

---

## Key Features

- 4-qubit-inspired 16-amplitude state representation
- Four configurable image-processing modes
- Fixed-point quantum-inspired transformations
- Hadamard-like amplitude mixing
- CNOT-style basis-state permutations
- Multi-cycle energy measurement
- Divider-free hardware scaling
- Self-checking verification environment
- Successful synthesis and timing closure

---

## Limitations

- The design emulates quantum-inspired state-vector operations using classical FPGA logic.
- It does not use physical qubits or quantum hardware.
- Processing is currently demonstrated on 2x2 image patches.
- DSP utilization is relatively high because of fixed-point amplitude multiplications.

---

## Future Work

- Processing complete images using a sliding 2x2 window
- Pipelining arithmetic stages for higher operating frequency
- Reducing DSP utilization through multiplier sharing
- Increasing the simulated state size
- Comparing outputs against classical image-processing kernels
- Integrating the accelerator with an FPGA image-streaming interface

---

## Author

**Raman R**

Electronics and Communication Engineering
Interests: VLSI, FPGA Design, Digital Hardware Architecture, RISC-V and Quantum-Inspired Computing

---

## License

This project is released under the MIT License.
