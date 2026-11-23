# Top-level system wrapper

> **Legacy (moved here from `rtl/system/` on 2026-11-18).** This wrapper belongs to the previous architecture (separate
> `Control`, `Memory` and the `conv-mux` engine). It is **not** used by the current stream-column cores in `rtl/conv*/`,
> which carry their own control inside the `Conv` module (see `rtl/README.md` and `docs/COMECE-AQUI.md`). It is kept
> because the `contrib/synthesis/sys-*` campaigns were run with it; their scripts and `list-file.txt` now point to the
> current locations of each source. Files deleted earlier and still named by those scripts:
> `rtl/system/testbench-netlist.sv`, `synthesis/_source/{logical_synthesis,power}.tcl` and
> `data/ifn9/sim/sim-032/pack_data.sv` (see the git history).
>
> **It does not build with today's sources.** Commit `510df996` (2026-05-16) renamed the size parameters of
> `pack_param` (`C1_SIZE`, `A1_SIZE`, `M1_SIZE`, ... to the `CONV_*` names) and the legacy controllers were not
> updated. To rebuild a `sys-*` campaign, check out `8a625e63` (2026-05-15), where the wrapper and its sources still
> agree and the original `rtl/...` paths exist. Checked on 2026-11-18 with `verilator --lint-only`: at `8a625e63`
> only 4 constant-width errors remain (accepted by the ModelSim flow used then); with today's sources the parameter
> names are missing.

`system.sv` composes the controller, convolution core, and SRAM models into a synthesizable accelerator.

## `System`
### Parameters
| Parameter | Type | Description |
|-----------|------|-------------|
| `NADDR` | `int` | Address width shared by the SRAM instances. |
| `NBITS` | `int` | Data width for feature, weight, and output elements. |
| `LATENCY` | `int` | Latency of the read SRAM used for features/weights. |
| `ROM` | `int` | When `1`, the read SRAM behaves as a ROM using `const_data`. |
| `QUANT` | `int` | Fractional precision for the convolution multipliers. |
| `N_WINDOW` | `int` | Number of Winograd windows per workload. |
| `N_CHANNEL_IN` | `int` | Number of input channels processed. |
| `N_CHANNEL_OUT` | `int` | Number of output channels generated. |
| `FEAT_INPUT_SIZE` | `int` | Input tile dimension (per side). |
| `FEAT_OUTPUT_SIZE` | `int` | Output tile dimension (per side). |
| `LAST_WINDOW` | `int` | Flag identifying the last window in the workload. |

### Ports
| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `clk` | Input | `logic` | Clock. |
| `reset` | Input | `logic` | Active-high reset. |
| `p_start` | Input | `logic` | Launches processing of a workload. |
| `p_end` | Output | `logic` | Pulses high when the workload completes. |

Internally, the module wires:
- `Control` (`contrib/rtl/control-sum/`, see its `README.md`) for sequencing.
- Two `Memory` instances (`rtl/mem/`, see its `README.md`) for read and write paths.
- The `Conv` engine (`contrib/rtl/conv-mux/`, see its `README.md`) for Winograd computation.

Simulation harnesses (`testbench.sv`, `sim.tcl`, `wave.do`) exercise the wrapper in this directory.
