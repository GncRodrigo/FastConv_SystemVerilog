# FPGA flow for streaming-column cores

This directory defines the shared ZCU104/XCZU7EV implementation and power
engine for the generated `trunc-column` cores. Family-specific manifests,
constraints, launchers, reports, and result summaries live under
`rtl/conv3x3/fpga_zcu104/` and `rtl/conv4x4/fpga_zcu104/`; this shared directory
retains the common scripts and testbench.

The 2026 campaigns (TCN9, IFN9, TCN16, WPN16) use the same workload packages
(`sim-032-3-3-normal-trunc`, Cin3/Cout3, now under `rtl/conv*/data/archive/`),
Vivado 2023.2 flow, 317 MHz clock, XCZU7EV part, `NADDR=12`, and output checker.
`NADDR=12` is the minimum width that covers each Cin3/Cout3 input/output memory
and matches the official streaming-column regression. Keep `NADDR=12` for those
packs; do not silently use the RTL's default `NADDR=16` in the FPGA comparison.

A manifest may carry its own settings as directive lines (comments for older
scripts):

| Directive | Effect |
| --- | --- |
| `#@nbits <n>` | datapath width, unless `STREAM_COLUMN_NBITS` is set |
| `#@dataset <dir>` | workload pack under `data/<alg>/sim/` (or `data/archive/<alg>/sim/`), unless `STREAM_COLUMN_DATASET` is set |
| `#@generic NAME=VALUE` | extra or overriding top-level generic for `synth_design` (default `NADDR=12 NBITS=<n>`) |

The current Cin3/Cout12 cores need `N_CHANNEL_OUT=12` and `NADDR=14`; see
`rtl/conv4x4/fpga_zcu104/manifests/trn16.rtl` and the TRN16 example in
`rtl/conv4x4/fpga_zcu104/README.md`. Only the default implementation flow
(`synth_impl.tcl`) reads `#@generic` and `STREAM_COLUMN_FPGA_PART` (default
`xczu7ev-ffvc1156-2-e`); the exploratory `synth_impl_*.tcl` scripts keep the
ZCU104 part and `NADDR=12` of the runs they produced.

`scripts/check_rtl.sh <fpga-config-dir> <variant> <family> [data-algorithm]`
runs the same testbench on the RTL in Xcelium with the manifest's settings, as a
check before a Vivado run.

The runner also supports an explicit datapath-width override through
`STREAM_COLUMN_NBITS` (default 20) and a workload-directory override through
`STREAM_COLUMN_DATASET` (default `sim-032-3-3-normal-trunc`). The width is passed
to Vivado's top-level generic and to the Xcelium testbench. For example, WPN16
at 16 bits uses the matching 16-bit package:

```bash
STREAM_COLUMN_NBITS=16 \
STREAM_COLUMN_DATASET=sim-032-3-3-normal-trunc-nbits16 \
rtl/conv4x4/fpga_zcu104/scripts/run_campaign.sh \
  /sim/tarsio/reports-wpn16-nbits16-<commit> wpn16
```

That pack is a width-narrowed copy of the canonical WPN16 truncated workload.
Its input, raw-weight, feature, and golden-output values fit signed 16 bits; its
provenance and hashes are recorded beside the package.

## Validation already performed locally

The port-level checker `tb/tb_power_stream_column.sv` was run in Verilator at
the 317 MHz clock period against each matching RTL, parameter package, matrix,
and truncated canonical workload. Each result had zero final-output mismatches:

| Algorithm | Input/output tile | MACs | Active cycles | Write beats | Physical words |
| --- | ---: | ---: | ---: | ---: | ---: |
| `tcn9` | 5x5 -> 3x3 | 5 | 10,138 | 2,700 | 8,100 |
| `ifn9` | 5x5 -> 3x3 | 6 | 11,038 | 2,700 | 8,100 |
| `tcn16` | 6x6 -> 4x4 | 6 | 7,691 | 2,304 | 9,216 |
| `wpn16` | 6x6 -> 4x4 | 8 | 8,843 | 2,304 | 9,216 |

These are RTL functional checks only, not FPGA implementation or power results.

On 2026-11-18, `scripts/check_rtl.sh` (Xcelium 23.03, RTL) reproduced `wpn16` at
16 bits with the archived `sim-032-3-3-normal-trunc-nbits16` pack (2,304 write
beats, 8,843 active cycles, zero mismatches) and checked `trn16` with its
Cin3/Cout12 pack (9,216 write beats, 10,800 output words, 35,357 active cycles,
zero mismatches).

## Paxos execution

First publish the exact source commit and verify it on the Paxos. Then load
Vivado 2023.2 and Xcelium 23.03 and run the campaign in a persistent tmux
session, directing artifacts outside Git:

```bash
source /usr/share/Modules/init/bash
module purge
module use /soft64/modulefiles
module load xilinx/vivado/2023.2 cadence/xcelium/2303
tmux new -s stream-column-fpga
# Inside tmux:
rtl/stream-column/fpga_zcu104/scripts/run_all.sh /tmp/stream-column-fpga-<commit>
```

To run selected configurations instead of the four standard algorithms, pass
their manifest IDs after the output directory. WPN16 m16/m32 use the canonical
`wpn16` parameter, matrix, and workload packages, while their manifests select
the corresponding RTL source:

```bash
rtl/stream-column/fpga_zcu104/scripts/run_all.sh \
  /sim/tarsio/reports-wpn16-m16-m32-<commit> wpn16_m16 wpn16_m32
```

Per algorithm, the script runs post-route implementation and reports, P0
vectorless power, post-implementation functional netlist simulation under
Xcelium, DUT and top-level SAIF captures between `p_start` and `p_end`, then
P3F power at typical and maximum operating corners. The P3F estimate is based
on functional activity and does not include SDF glitch activity. Xcelium must
report `STREAM_COLUMN_POWER_PASS` in both captures before Vivado imports SAIF.

All DCPs, netlists, SAIF files, simulator libraries and reports are placed in
the supplied output directory; they are not source artifacts and should not
be committed. Preserve the text logs, utilization/timing reports, power reports,
SAIF mapping reports and checksums as campaign evidence.
