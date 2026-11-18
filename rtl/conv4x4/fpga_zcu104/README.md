# FPGA campaigns for Conv4x4

This directory holds the ZCU104/XCZU7EV FPGA configuration, per-algorithm
manifests, entry point, and campaign evidence for the Conv4x4 streaming-column
cores. The implementation scripts and testbench are shared from
`rtl/stream-column/fpga_zcu104/` to keep the FPGA methodology identical across
the supported convolution sizes.

## Current example: TRN16 (Cin3/Cout12, 16 bits)

`trn16` is the starting point for taking a current core to an FPGA. Its
manifest uses the RTL of the ASIC configuration
`rtl/conv4x4/synthesis/conv-trn16-i60-h17-t16-o16-m08-stream16-prefetch24-rowconst8-round-column-frac0-extra0-nbits16-cin3-cout12`
and carries its own width, workload, and generics as directives, so no
environment overrides are needed:

```text
#@nbits 16
#@dataset sim-032-3-12-normal-trunc-frac0-extra0-round-nbits16
#@generic N_CHANNEL_OUT=12
#@generic NADDR=14
```

1. RTL check, before spending a Vivado run (Xcelium, a few seconds):

   ```bash
   module load xcelium/2303        # cadence/xcelium/2303 on the Paxos
   rtl/stream-column/fpga_zcu104/scripts/check_rtl.sh rtl/conv4x4/fpga_zcu104 trn16 4
   ```

   It must print `STREAM_COLUMN_POWER_PASS ... mismatches=0`. On 2026-11-18 it
   gave 9,216 write beats, 10,800 output words, zero mismatches, and 35,357
   active cycles. As a negative control, the same core against the WPN16 pack
   (`check_rtl.sh rtl/conv4x4/fpga_zcu104 trn16 4 wpn16`) fails with 10,166
   mismatches.
2. Implementation, power, and post-route functional simulation on the Paxos
   (Vivado 2023.2 + Xcelium 23.03, inside tmux):

   ```bash
   rtl/conv4x4/fpga_zcu104/scripts/run_campaign.sh /sim/tarsio/reports-trn16-<commit> trn16
   ```

   For another Zynq UltraScale+ device set the part, e.g. for the Kria K26
   `STREAM_COLUMN_FPGA_PART=xck26-sfvc784-2LV-c`. The constraints only define
   the 317 MHz clock (`constraints/zcu104_317mhz.xdc`), so they are board
   independent; change the period there if the target clock differs.

The full flow passed on 2026-11-18 (commit `4d76f4fa`): 5,884 LUT, 2,049 FF,
8 DSP, WNS `+0.095 ns` at 317 MHz, post-route golden with zero mismatches, and
0.458 W P3F typical dynamic power; see
[results/trn16-nbits16-cin3-cout12-4d76f4fa.md](results/trn16-nbits16-cin3-cout12-4d76f4fa.md).

### Using TRN16 in your own Vivado project (e.g. a Kria board)

The core needs only the three sources of `manifests/trn16.rtl` (no package
import): `rtl/conv4x4/mult-matrices/trn16/mult_matrices.sv`,
`rtl/multip/multip.sv`, and the core
`rtl/conv4x4/conv-trn16-i60-h17-t16-o16-m08-stream16-prefetch24-rowconst8-round-column.sv`.
Top module `Conv`, generics `NBITS=16 N_CHANNEL_OUT=12 NADDR=14` (the other
defaults already match: `N_CHANNEL_IN=3`, `NUM_MULT=8`, `ROUND=1`,
`WEIGHT_FRAC_BITS=0`, `EXTRA_FRAC_BITS=0`).

- **Interface:** `p_start`/`p_end`, one read port to the input memory (one
  6-word column per beat) and one read/write port to the output memory (one
  4-word column per beat). There is no AXI and no separate controller: the
  control is inside `Conv`. Memory layout and timing are those of
  `tb/tb_power_stream_column.sv` in `rtl/stream-column/fpga_zcu104/`, which is
  the reference for a BRAM wrapper.
- **I/O:** as a bare top the core uses 261 user I/O (`reports/trn16-4d76f4fa/trn16/io.rpt`).
  That fits the ZCU104 but may exceed the user I/O of a smaller device such as
  the Kria K26 SOM; check its datasheet. On such a device, put the memories
  next to the core in a wrapper (the real integration) or synthesize the core
  out of context (`synth_design -mode out_of_context`) to look at area and
  timing.
- **Simulation:** the self-checking testbench is
  `rtl/stream-column/fpga_zcu104/tb/tb_power_stream_column.sv` with
  `rtl/conv4x4/pack-param/trn16/pack_param.sv`, the `pack_data.sv` of the
  dataset above, and `rtl/mem/mem.sv`, defining `STREAM_COLUMN_NBITS=16`. It
  prints `STREAM_COLUMN_POWER_PASS ... mismatches=0` on success. Only Xcelium
  was used here; Verilator 5 rejects the long lines of `pack_data.sv`, and
  Vivado's simulator was not tried.
- **Reference numbers** on the ZCU104 at 317 MHz are in
  [results/trn16-nbits16-cin3-cout12-4d76f4fa.md](results/trn16-nbits16-cin3-cout12-4d76f4fa.md).

To add another current core, copy `manifests/trn16.rtl`, replace the RTL line
by the core of its ASIC configuration (`rtl/conv4x4/synthesis/<config>/list-file.txt`,
without `pack_data.sv`, which is only the simulation workload; `pack_param.sv` and
`pack_data.sv` are added by the flow), take `#@generic` values from
`top-parameters.txt`, size `NADDR` for the larger of the input
(`$size(const_data)` in `pack_data.sv`) and output (`N_CHANNEL_OUT`x32x32) memories,
and add the variant to the `case` at the end of
`rtl/stream-column/fpga_zcu104/scripts/run_all.sh`.

## Manifests

Supported manifests:

| ID | Algorithm/configuration | RTL source |
| --- | --- | --- |
| `tcn16` | TCN16, 6 MACs | `conv-tcn16-i60-h15-t12-o16-m06-stream12-prefetch24-rowconst6-trunc-column.sv` |
| `tcn16_m12` | TCN16, 12 MACs, 2 Hadamard rows/cycle | `conv-tcn16-i60-h21-t24-o16-m12-stream12-prefetch24-rowconst6-trunc-column.sv` |
| `tcn16_m18` | TCN16, 18 MACs, 3 Hadamard rows/cycle | `conv-tcn16-i60-h27-t36-o16-m18-stream12-prefetch24-rowconst6-trunc-column.sv` |
| `wpn16` | WPN16, 8 MACs | `conv-wpn16-i60-h17-t16-o16-m08-stream16-prefetch24-rowconst8-trunc-column.sv` |
| `wpn16_m16` | WPN16, 16 MACs | `conv-wpn16-i60-h25-t32-o16-m16-stream16-prefetch24-rowconst8-trunc-column.sv` |
| `wpn16_m32` | WPN16, 32 MACs | `conv-wpn16-i60-h41-t64-o16-m32-stream16-prefetch24-rowconst8-trunc-column.sv` |
| `wpn16_pipe` | WPN16, 8 MACs, registered feature-transform boundary | `conv-wpn16-pipe-i60-h17-t16-o16-m08-stream16-prefetch24-rowconst8-trunc-column.sv` |
| `wpn16_pipe_both` | WPN16, 8 MACs, registered feature- and weight-transform boundaries | same RTL, `PIPE_WEIGHT_TRANSFORM=1` |
| `trn16` | TRN16 (ternary), 8 MACs, round, Cin3/Cout12 workload | `conv-trn16-i60-h17-t16-o16-m08-stream16-prefetch24-rowconst8-round-column.sv` |

The TCN16 and `wpn16_pipe` RTL now lives in `rtl/conv4x4/archive/{tcn16,wpn16}/`
and the Cin3/Cout3 workload packs (`sim-032-3-3-normal-trunc*`) in
`rtl/conv4x4/data/archive/<alg>/sim/`; the manifests and `run_all.sh` point
there (2026-11-18). To reproduce a recorded campaign bit for bit, use the
commit written in its result file.

The three TCN16 variants were functionally checked locally with the same
generated `NBITS=16` truncated workload. Each produced 8,100 valid output
words, 576 inverse tiles, and zero golden mismatches:

| Variant | MACs | `p_end` cycles |
| --- | ---: | ---: |
| TCN16 m06 | 6 | 7,699 |
| TCN16 m12 | 12 | 5,971 |
| TCN16 m18 | 18 | 5,395 |

These are RTL simulation counts, not post-route implementation or timing
results. The 16-bit TCN16 package was recomputed with the finite-width Python
simulation; it is not a width-only edit of the 20-bit golden.

`wpn16_pipe` is an experimental timing variant of the standard WPN16 m08
core. It registers the `MatrixC0` partial results before `MatrixC1`, adding one
cycle per spatial tile while leaving the canonical RTL and the weight transform
unchanged. The first 32-core trial at 16 bits passed functional simulation but
failed post-route timing at 317 MHz; its exact result and critical path are
preserved in [wpn16-n32-featurepipe-5dad37b9.md](results/wpn16-n32-featurepipe-5dad37b9.md).

`wpn16_pipe_both` retains that feature-transform boundary and additionally
registers the first axis of the separable weight transform before evaluating
the second axis. This preserves the full-precision numerator until the final
arithmetic shift, so it is intended to preserve the truncation contract. Its
16-bit / 32-core flow uses algorithm `wpn16_pipe_both_nbits16` in the shared
`synth_replicas.tcl` engine. The canonical 16-bit RTL golden passed, and the
32-core OOC post-route implementation passed timing at 317 MHz with WNS
`+0.043 ns`. The result, critical path, OOC clock-constraint caveat, and reports
are preserved in
[wpn16-n32-pipeboth-317mhz-94eb5f85.md](results/wpn16-n32-pipeboth-317mhz-94eb5f85.md).
This is an IP-level OOC timing result; replicated post-route functional
simulation and power analysis have not been run.

WPN16 m16 and m32 use the canonical WPN16 parameter, matrix, and workload
packages. The common workload packages, clock, and P3F procedure are documented
in the shared flow README. Raw reports go in `reports/`; curated tables and
provenance go in `results/`. DCP, SAIF, simulator databases, and compiled
UNISIM libraries are excluded from Git.

The FPGA comparison uses a 16-bit datapath. Select the matching 16-bit workload
pack and set both flow overrides (the RTL sources themselves retain their
20-bit default):

```bash
STREAM_COLUMN_NBITS=16 \
STREAM_COLUMN_DATASET=sim-032-3-3-normal-trunc-nbits16 \
rtl/conv4x4/fpga_zcu104/scripts/run_campaign.sh \
  /sim/tarsio/reports-wpn16-nbits16-<commit> wpn16
```

TCN16 m12/m18 use the generated 16-bit TCN16 pack in the same way:

```bash
STREAM_COLUMN_NBITS=16 \
STREAM_COLUMN_DATASET=sim-032-3-3-normal-trunc-nbits16 \
rtl/conv4x4/fpga_zcu104/scripts/run_campaign.sh \
  /sim/tarsio/reports-tcn16-m12-m18-nbits16-<commit> tcn16_m12 tcn16_m18
```

## Run

On Paxos, verify the exact published commit and load Vivado 2023.2 and Xcelium
23.03. Run the full campaign from a `tmux` session with outputs outside the
checkout:

```bash
rtl/conv4x4/fpga_zcu104/scripts/run_campaign.sh \
  /sim/tarsio/reports-conv4x4-<commit> tcn16 wpn16 wpn16_m16 wpn16_m32
```

The TCN16 parallelism sweep can be run independently (including the original
6-MAC baseline) with:

```bash
STREAM_COLUMN_NBITS=16 \
STREAM_COLUMN_DATASET=sim-032-3-3-normal-trunc-nbits16 \
rtl/conv4x4/fpga_zcu104/scripts/run_campaign.sh \
  /sim/tarsio/reports-tcn16-6-12-18-nbits16-<commit> tcn16 tcn16_m12 tcn16_m18
```

The campaign uses the local manifests and constraints in this directory while
calling the shared implementation engine.
