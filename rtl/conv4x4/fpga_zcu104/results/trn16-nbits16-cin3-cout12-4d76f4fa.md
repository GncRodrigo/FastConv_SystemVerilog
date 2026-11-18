# TRN16 FPGA campaign: 8 MACs, 16 bits, Cin3/Cout12 workload

## Result

TRN16 (ternary F(4,3) of 8 products, cost 340, round, frac0) is the first
current Cin3/Cout12 core taken through the full ZCU104 flow. On
`xczu7ev-ffvc1156-2-e` it meets the 317 MHz constraint after routing
(WNS `+0.095 ns`), passes the post-route functional golden test in both SAIF
captures (10,800 outputs, zero mismatches), and has P3F power reports.

The tables below are the output of

```bash
python3 rtl/stream-column/fpga_zcu104/scripts/collect_campaign.py \
  rtl/conv4x4/fpga_zcu104/reports/trn16-4d76f4fa trn16
```

| Variant | LUT | FF | DSP | RAMB36/18 | Routed WNS | TNS | Timing |
| :-- | --: | --: | --: | --: | --: | --: | :-- |
| `trn16` | 5,884 | 2,049 | 8 | 0/0 | +0.095 ns | 0.000 ns | Pass |

| Variant | Capture | Write beats | Physical words | Final outputs | Mismatches | Active cycles |
| :-- | :-- | --: | --: | --: | --: | --: |
| `trn16` | dut | 9,216 | 36,864 | 10,800 | 0 | 35,357 |
| `trn16` | top | 9,216 | 36,864 | 10,800 | 0 | 35,357 |

| Variant | Estimate | Corner | Dynamic (W) | Device static (W) | Total on-chip (W) | Confidence | DUT SAIF match | Top SAIF match |
| :-- | :-- | :-- | --: | --: | --: | :-- | :-- | :-- |
| `trn16` | P3F | typical | 0.458 | 0.594 | 1.052 | High | 12,229/12,489 (97.92%) | 12,489/12,489 (100.00%) |
| `trn16` | P3F | maximum | 0.458 | 0.817 | 1.275 | High | 12,229/12,489 (97.92%) | 12,489/12,489 (100.00%) |
| `trn16` | vectorless | typical | 0.330 | 0.593 | 0.923 | Low | - | - |
| `trn16` | vectorless | maximum | 0.330 | 0.815 | 1.144 | Low | - | - |

P3F typical dynamic breakdown (W):

| Variant | Clocks | CLB Logic | Signals | DSP | I/O |
| :-- | --: | --: | --: | --: | --: |
| `trn16` | 0.021 | 0.048 | 0.079 | 0.014 | 0.295 |

P3F uses the post-implementation functional netlist without SDF, so it does
not include delay-induced glitch activity, and it is not a board measurement.
As in the earlier campaigns, the core exposes its memory ports as physical
I/O, which dominates the estimated dynamic power (0.295 of 0.458 W).

## Not directly comparable with the WPN16 records

The WPN16 m08 record ([wpn16-8-16-32-nbits16-ae16c90e.md](wpn16-8-16-32-nbits16-ae16c90e.md):
6,899 LUT, 2,080 FF, 8 DSP, 0.573 W typical dynamic) used the Cin3/Cout3
truncated workload, `NADDR=12`, and the trunc-column RTL. This run uses the
Cin3/Cout12 round workload, `NADDR=14`, `N_CHANNEL_OUT=12`, and the
round-column RTL. Area is indicative; power, cycles, and energy need both
cores on the same workload before any comparison.

## Timing

The worst routed path starts at `r_weight_spatial_reg[8][4]` and ends at
`r_input_weight_reg[4][14]` (weight transform): 2.978 ns, 1.148 ns logic and
1.830 ns routing, 10 logic levels (3 `CARRY8`).

## First attempt (13525bed)

The first run, at commit `13525bed`, finished implementation with the same
area and WNS, but both SAIF captures stopped at the fixed 90 us timeout of
`capture_{dut,top}_saif.tcl` (`P3F_TIMEOUT_BEFORE_P_END`): this workload
needs about 112 us (35,357 cycles at 317 MHz). Commit `4d76f4fa` raised the
timeout to 195 us, below the 200 us testbench watchdog, and the full flow was
rerun from scratch. The first run is not kept.

## Reproduction and provenance

| Item | Value |
| :--- | :---- |
| Source commit | `4d76f4fac577e7bf5925ab6c9fd7e8774979f0f5` |
| Host | `paxos.inf.pucrs.br` (worktree `/sim/tarsio.onofrio/fpga-trn16-4d76f4fa`) |
| Vivado / Xcelium | 2023.2 / 23.03-s003 |
| Device | ZCU104, `xczu7ev-ffvc1156-2-e` |
| Target | 317 MHz (3.154574 ns) |
| Generics | `NADDR=14 NBITS=16 N_CHANNEL_OUT=12` (from `manifests/trn16.rtl`) |
| Workload | `rtl/conv4x4/data/trn16/sim/sim-032-3-12-normal-trunc-frac0-extra0-round-nbits16` |
| Workload SHA-256 | `1488419cc77fd896da75b932317e88d43bc4ffdc2b91147f63088de9a2fa96ed` |
| RTL | `conv-trn16-i60-h17-t16-o16-m08-stream16-prefetch24-rowconst8-round-column.sv` |
| RTL SHA-256 | `cf44b636d4b8b3fe1a9c4ca461f7f5517633e51f7126aa2235a86fb0642abc8e` |
| tmux session | `fastconv-fpga-trn16b-20261118` |
| Command | `rtl/conv4x4/fpga_zcu104/scripts/run_campaign.sh /sim/tarsio.onofrio/fpga-reports/trn16-4d76f4fa trn16` |
| Text reports | [`../reports/trn16-4d76f4fa/`](../reports/trn16-4d76f4fa/) |
| DCP, netlist, SAIF | on the Paxos, `/sim/tarsio.onofrio/fpga-reports/trn16-4d76f4fa/`; hashes in `checksums.sha256` |
