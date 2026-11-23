#!/usr/bin/env bash
set -euo pipefail

# RTL pre-check of an FPGA manifest before spending a Vivado run: compiles the
# manifest sources with the same workload package, width and generics that
# run_all.sh / synth_impl.tcl would use and runs tb_power_stream_column in
# Xcelium, the simulator of the netlist captures (RTL, not the post-route
# netlist). Passing prints
# STREAM_COLUMN_POWER_PASS; any golden mismatch is fatal.
#
# Usage: check_rtl.sh <fpga-config-dir> <variant> <family> [data-algorithm] [build-dir]
#   e.g. check_rtl.sh rtl/conv4x4/fpga_zcu104 trn16 4
# Needs Xcelium (module load cadence/xcelium/2303 on the Paxos, xcelium/2303 on
# the gaphs machines). Verilator 5 rejects the long lines of the newer packs.
if [[ $# -lt 3 ]]; then
  printf 'usage: %s <fpga-config-dir> <variant> <family> [data-algorithm] [build-dir]\n' "$0" >&2
  exit 2
fi
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
bench_dir=$(cd -- "$script_dir/.." && pwd)
repo_root=$(cd -- "$bench_dir/../../.." && pwd)
config_dir=$(cd -- "$1" && pwd)
variant=$2
family=$3
data_algorithm=${4:-$variant}
build_dir=${5:-$(mktemp -d "${TMPDIR:-/tmp}/fpga-rtl-check-$variant.XXXXXX")}
manifest="$config_dir/manifests/$variant.rtl"
[[ -s "$manifest" ]] || { printf 'missing manifest %s\n' "$manifest" >&2; exit 1; }

directive() { sed -n "s/^#@$1[[:space:]]\{1,\}//p" "$manifest" | tail -n 1; }
nbits=${STREAM_COLUMN_NBITS:-$(directive nbits)}
nbits=${nbits:-20}
dataset=${STREAM_COLUMN_DATASET:-$(directive dataset)}
dataset=${dataset:-sim-032-3-3-normal-trunc}
conv_dir="$repo_root/rtl/conv${family}x${family}"
params="$conv_dir/pack-param/$data_algorithm/pack_param.sv"
data="$conv_dir/data/$data_algorithm/sim/$dataset/pack_data.sv"
[[ -s "$data" ]] || data="$conv_dir/data/archive/$data_algorithm/sim/$dataset/pack_data.sv"
[[ -s "$params" && -s "$data" ]] || { printf 'missing params or data: %s %s\n' "$params" "$data" >&2; exit 1; }

sources=()
while IFS= read -r line; do
  line=${line%%$'\r'}
  [[ -z "$line" || "$line" == \#* ]] && continue
  sources+=("$repo_root/$line")
done < "$manifest"

# In RTL mode the testbench derives N_CHANNEL_IN/OUT and NADDR from the
# workload package; the manifest "#@generic" lines must give the same values
# to Vivado, since the post-route netlist has them fixed.
printf 'variant=%s NBITS=%s dataset=%s\ndata=%s\nbuild=%s\n' "$variant" "$nbits" "$dataset" "$data" "$build_dir"
sed -n 's/^#@generic[[:space:]]\{1,\}/manifest generic: /p' "$manifest"

(
  cd "$build_dir"
  : > cds.lib  # keeps xrun from reading libraries listed in ~/cds.lib
  xrun -64bit -cdslib cds.lib -sv -timescale 1ns/1ps -access +r -define STREAM_COLUMN_NBITS="$nbits" \
    -top tb_power_stream_column -l xrun.log \
    "$params" "$data" "$repo_root/rtl/mem/mem.sv" "${sources[@]}" \
    "$bench_dir/tb/tb_power_stream_column.sv" > /dev/null 2>&1
) || true
grep -E 'STREAM_COLUMN_POWER|POWER_RESULT|POWER_GOLDEN|\*E,|\*F,' "$build_dir/xrun.log" || true
grep -q STREAM_COLUMN_POWER_PASS "$build_dir/xrun.log"
