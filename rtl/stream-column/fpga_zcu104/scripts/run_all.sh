#!/usr/bin/env bash
set -euo pipefail

# Full ZCU104/XCZU7EV post-route functional-SAIF power campaign.
# Run this script inside tmux on the Paxos. Outputs are kept outside Git.
if [[ $# -lt 1 ]]; then
  printf 'usage: %s <output-root> [algorithm ...]\n' "$0" >&2
  exit 2
fi
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
bench_dir=$(cd -- "$script_dir/.." && pwd)
repo_root=$(cd -- "$bench_dir/../../.." && pwd)
config_dir=${STREAM_COLUMN_FPGA_CONFIG_DIR:-$bench_dir}
constraints=${STREAM_COLUMN_FPGA_XDC:-$config_dir/constraints/zcu104_317mhz.xdc}
impl_flow=${STREAM_COLUMN_FPGA_IMPL_FLOW:-default}
# Width and workload: the environment wins, then the manifest's "#@nbits" and
# "#@dataset" lines, then the historical defaults (20 bits, Cin3/Cout3 pack).
nbits_env=${STREAM_COLUMN_NBITS:-}
dataset_env=${STREAM_COLUMN_DATASET:-}
case "$impl_flow" in
  default) synth_script="$script_dir/synth_impl.tcl" ;;
  explore_postroute_physopt) synth_script="$script_dir/synth_impl_explore_postroute_physopt.tcl" ;;
  *) printf 'unknown implementation flow: %s\n' "$impl_flow" >&2; exit 2 ;;
esac
output_root=$(mkdir -p -- "$1" && cd -- "$1" && pwd)
simlib_dir="$output_root/simlibs_unisim"
mkdir -p "$output_root"

for tool in vivado xrun; do
  command -v "$tool" >/dev/null || { printf 'tool not found: %s\n' "$tool" >&2; exit 127; }
done

vivado_exe=$(readlink -f "$(command -v vivado)")
vivado_root=$(cd -- "$(dirname -- "$vivado_exe")/.." && pwd)
glbl_v="$vivado_root/data/verilog/src/glbl.v"
[[ -f "$glbl_v" ]] || { printf 'cannot locate glbl.v under %s\n' "$vivado_root" >&2; exit 1; }

# Value of a "#@<key> <value>" directive in a manifest (empty if absent).
manifest_directive() {
  sed -n "s/^#@$2[[:space:]]\{1,\}//p" "$1" | tail -n 1
}

run_one() {
  local algorithm=$1 family=$2 data_algorithm=${3:-$1}
  local run_dir="$output_root/$algorithm"
  local manifest="$config_dir/manifests/$algorithm.rtl"
  [[ -s "$manifest" ]] || { printf 'missing manifest %s\n' "$manifest" >&2; return 1; }
  local nbits=${nbits_env:-$(manifest_directive "$manifest" nbits)}
  local dataset=${dataset_env:-$(manifest_directive "$manifest" dataset)}
  nbits=${nbits:-20}
  dataset=${dataset:-sim-032-3-3-normal-trunc}
  [[ "$nbits" =~ ^[0-9]+$ ]] && (( nbits > 0 )) || {
    printf 'NBITS must be a positive integer: %s\n' "$nbits" >&2
    return 2
  }
  export STREAM_COLUMN_NBITS="$nbits"
  local conv_dir="$repo_root/rtl/conv${family}x${family}"
  local params="$conv_dir/pack-param/$data_algorithm/pack_param.sv"
  local data="$conv_dir/data/$data_algorithm/sim/$dataset/pack_data.sv"
  # The Cin3/Cout3 packs of the 2026 campaigns were moved to data/archive/.
  [[ -s "$data" ]] || data="$conv_dir/data/archive/$data_algorithm/sim/$dataset/pack_data.sv"
  local matrices="$conv_dir/mult-matrices/$data_algorithm/mult_matrices.sv"
  mkdir -p "$run_dir"
  [[ -s "$params" && -s "$data" && -s "$matrices" ]] || {
    printf 'missing source inputs for %s (params %s, data %s, matrices %s)\n' \
      "$algorithm" "$params" "$data" "$matrices" >&2; return 1;
  }
  printf 'variant=%s NBITS=%s dataset=%s data=%s\n' "$algorithm" "$nbits" "$dataset" "$data" \
    | tee -a "$output_root/campaign_metadata.txt"
  grep -Eq "localparam int NBITS = ${nbits};" "$data" &&
    grep -Eq "localparam int WEIGHT_NBITS = ${nbits};" "$data" || {
      printf 'workload package width does not match STREAM_COLUMN_NBITS=%s: %s\n' \
        "$nbits" "$data" >&2
      return 1
    }
  sha256sum "$manifest" "$params" "$data" "$matrices" \
    "$repo_root/$(tail -n 1 "$manifest")" "$bench_dir/tb/tb_power_stream_column.sv" \
    >> "$output_root/checksums.sha256"

  vivado -mode batch -source "$synth_script" \
    -log "$output_root/${algorithm}.synth.vivado.log" \
    -journal "$output_root/${algorithm}.synth.vivado.jou" \
    -tclargs "$repo_root" "$output_root" "$algorithm" "$manifest" "$constraints"
  vivado -mode batch -source "$script_dir/power_vectorless.tcl" \
    -log "$output_root/${algorithm}.vectorless.vivado.log" \
    -journal "$output_root/${algorithm}.vectorless.vivado.jou" \
    -tclargs "$output_root" "$algorithm"
  vivado -mode batch -source "$script_dir/prepare_funcsim.tcl" \
    -log "$output_root/${algorithm}.funcsim_prepare.vivado.log" \
    -journal "$output_root/${algorithm}.funcsim_prepare.vivado.jou" \
    -tclargs "$run_dir/design_routed.dcp" "$run_dir/design_routed_funcsim.v" "$simlib_dir"
  sha256sum "$run_dir/design_routed.dcp" "$run_dir/design_routed_funcsim.v" \
    >> "$output_root/checksums.sha256"

  for capture in dut top; do
    local capture_dir="$run_dir/$capture"
    mkdir -p "$capture_dir"
    (
      cd "$capture_dir"
      local capture_tcl="$script_dir/capture_${capture}_saif.tcl"
      xrun -64bit -sv -access +r -cdslib "$simlib_dir/cds.lib" \
        -hdlvar "$simlib_dir/hdl.var" -reflib "$simlib_dir/unisims_ver:unisims_ver" \
        -define GATE_LEVEL -define STREAM_COLUMN_NBITS=$nbits \
        -top tb_power_stream_column -top glbl -timescale 1ns/1ps \
        -input "$capture_tcl" -l xrun.log \
        "$params" "$data" "$repo_root/rtl/mem/mem.sv" \
        "$run_dir/design_routed_funcsim.v" "$glbl_v" \
        "$bench_dir/tb/tb_power_stream_column.sv"
    )
    [[ -s "$capture_dir/activity_${capture}.saif" ]] || {
      printf 'missing %s SAIF for %s\n' "$capture" "$algorithm" >&2; return 1;
    }
    grep -q 'STREAM_COLUMN_POWER_PASS' "$capture_dir/xrun.log" || {
      printf 'functional golden marker missing for %s/%s\n' "$algorithm" "$capture" >&2; return 1;
    }
    ! grep -q '^P3F_TIMEOUT_BEFORE_P_END$' "$capture_dir/xrun.log" || {
      printf 'SAIF capture timed out for %s/%s\n' "$algorithm" "$capture" >&2; return 1;
    }
    sha256sum "$capture_dir/activity_${capture}.saif" >> "$output_root/checksums.sha256"
  done

  vivado -mode batch -source "$script_dir/power_p3f.tcl" \
    -log "$output_root/${algorithm}.p3f.vivado.log" \
    -journal "$output_root/${algorithm}.p3f.vivado.jou" \
    -tclargs "$output_root" "$algorithm" \
      "$run_dir/dut/activity_dut.saif" "$run_dir/top/activity_top.saif"
  printf 'FPGA_POWER_VARIANT_COMPLETE algorithm=%s implementation_flow=%s\n' \
    "$algorithm" "$impl_flow"
}

printf 'host=%s\nrepo_root=%s\ncommit=%s\nvivado=%s\nxrun=%s\nimplementation_flow=%s\npart=%s\nNBITS_override=%s\ndataset_override=%s\n' \
  "$(hostname)" "$repo_root" "$(git -C "$repo_root" rev-parse HEAD)" \
  "$(vivado -version | sed -n '1p')" "$(xrun -version 2>&1 | sed -n '1p')" "$impl_flow" \
  "${STREAM_COLUMN_FPGA_PART:-xczu7ev-ffvc1156-2-e}" "${nbits_env:-none}" "${dataset_env:-none}" \
  | tee "$output_root/campaign_metadata.txt"

if [[ $# -gt 1 ]]; then
  shift
  for algorithm in "$@"; do
    case "$algorithm" in
      wpn16_m16|wpn16_m32) run_one "$algorithm" 4 wpn16 ;;
      tcn9|ifn9) run_one "$algorithm" 3 ;;
      ifn9_m12|ifn9_m18) run_one "$algorithm" 3 ifn9 ;;
      tcn16|wpn16) run_one "$algorithm" 4 ;;
      tcn16_m12|tcn16_m18) run_one "$algorithm" 4 tcn16 ;;
      trn16) run_one "$algorithm" 4 ;;
      *) printf 'unknown algorithm variant: %s\n' "$algorithm" >&2; exit 2 ;;
    esac
  done
else
  run_one tcn9 3
  run_one ifn9 3
  run_one tcn16 4
  run_one wpn16 4
fi
printf 'FPGA_POWER_CAMPAIGN_COMPLETE output_root=%s implementation_flow=%s\n' \
  "$output_root" "$impl_flow"
