#!/usr/bin/env python3
"""Markdown tables of a run_all.sh campaign, read from its text reports.

Usage: collect_campaign.py <campaign-dir> <variant> [<variant> ...]

<campaign-dir> is the output root of run_all.sh / run_campaign.sh, or its copy
under rtl/conv*/fpga_zcu104/reports/ (only the text reports are needed:
utilization.rpt, timing_summary.rpt, power_*.rpt, {dut,top}/xrun.log and
<variant>.p3f.vivado.log). Prints the implementation, functional, and power tables
used in results/*.md, so the numbers there are not typed by hand.
"""

import re
import sys
from pathlib import Path


def read(path):
    return path.read_text(errors="replace") if path.exists() else ""


def utilization(run):
    text = read(run / "utilization.rpt")
    header = next((l for l in text.splitlines() if re.match(r"\|\s*Instance\s*\|", l)), None)
    top = next((l for l in text.splitlines() if re.match(r"\|\s*Conv\s*\|", l)), None)
    if not header or not top:
        return {}
    names = [c.strip() for c in header.strip("|").split("|")]
    values = [c.strip() for c in top.strip("|").split("|")]
    return dict(zip(names, values))


def timing(run):
    text = read(run / "timing_summary.rpt")
    m = re.search(r"WNS\(ns\)\s+TNS\(ns\)\s+TNS Failing Endpoints.*\n\s*-+.*\n\s*(\S+)\s+(\S+)\s+(\S+)", text)
    met = "All user specified timing constraints are met." in text
    if not m:
        return None
    return {"wns": float(m.group(1)), "tns": float(m.group(2)), "failing": int(m.group(3)), "met": met}


def power(run, kind, corner):
    text = read(run / f"power_{kind}_{corner}.rpt")
    out = {}
    for key, label in (("total", "Total On-Chip Power (W)"), ("dynamic", "Dynamic (W)"),
                       ("static", "Device Static (W)"), ("confidence", "Confidence Level")):
        m = re.search(r"\|\s*" + re.escape(label) + r"\s*\|\s*([^|]+?)\s*\|", text)
        if m:
            out[key] = m.group(1)
    for key in ("Clocks", "CLB Logic", "Signals", "DSPs", "I/O"):
        m = re.search(r"^\|\s*" + re.escape(key) + r"\s*\|\s*([0-9.<]+)\s*\|", text, re.M)
        if m:
            out[key] = m.group(1)
    return out


def saif_match(root, variant, which, corner):
    """Matched nets from the P3F Vivado log: power_p3f.tcl reads the DUT SAIF
    and then the top SAIF, for the typical and then the maximum corner."""
    found = re.findall(r"Design nets matched = (\d+) of (\d+)", read(root / f"{variant}.p3f.vivado.log"))
    i = {"typical": 0, "maximum": 2}[corner] + {"internal": 0, "ports": 1}[which]
    if len(found) < 4:
        return "?"
    m, t = map(int, found[i])
    return f"{m:,}/{t:,} ({100 * m / t:.2f}%)"


def golden(run, capture):
    text = read(run / capture / "xrun.log")
    m = re.search(r"STREAM_COLUMN_POWER_PASS writes=(\d+) physical_words=(\d+) final_words=(\d+) "
                  r"mismatches=(\d+) active_cycles=(\d+)", text)
    if m:
        return dict(zip(("writes", "physical", "final", "mismatches", "cycles"), map(int, m.groups())))
    fail = re.search(r"POWER_RESULT_\w+[^\n]*", text)
    return {"fail": fail.group(0) if fail else "no result"}


def fmt_int(s):
    try:
        return f"{int(s):,}"
    except (TypeError, ValueError):
        return s or "?"


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    root = Path(sys.argv[1])
    variants = sys.argv[2:]

    print("| Variant | LUT | FF | DSP | RAMB36/18 | Routed WNS | TNS | Timing |")
    print("| :-- | --: | --: | --: | --: | --: | --: | :-- |")
    for v in variants:
        u, t = utilization(root / v), timing(root / v)
        tim = "?" if t is None else ("Pass" if t["met"] and t["wns"] >= 0 else f"Fail; {t['failing']} endpoints")
        wns = "?" if t is None else f"{t['wns']:+.3f} ns"
        tns = "?" if t is None else f"{t['tns']:.3f} ns"
        print(f"| `{v}` | {fmt_int(u.get('Total LUTs'))} | {fmt_int(u.get('FFs'))} | {fmt_int(u.get('DSP Blocks'))} | "
              f"{u.get('RAMB36', '?')}/{u.get('RAMB18', '?')} | {wns} | {tns} | {tim} |")
    print()
    print("| Variant | Capture | Write beats | Physical words | Final outputs | Mismatches | Active cycles |")
    print("| :-- | :-- | --: | --: | --: | --: | --: |")
    for v in variants:
        for c in ("dut", "top"):
            g = golden(root / v, c)
            if "fail" in g:
                print(f"| `{v}` | {c} | {g['fail']} | | | | |")
            else:
                print(f"| `{v}` | {c} | {g['writes']:,} | {g['physical']:,} | {g['final']:,} | {g['mismatches']} | "
                      f"{g['cycles']:,} |")
    print()
    print("| Variant | Estimate | Corner | Dynamic (W) | Device static (W) | Total on-chip (W) | Confidence | "
          "DUT SAIF match | Top SAIF match |")
    print("| :-- | :-- | :-- | --: | --: | --: | :-- | :-- | :-- |")
    for v in variants:
        for kind in ("p3f", "vectorless"):
            for corner in ("typical", "maximum"):
                p = power(root / v, kind, corner)
                dut = saif_match(root, v, "internal", corner) if kind == "p3f" else "-"
                top = saif_match(root, v, "ports", corner) if kind == "p3f" else "-"
                print(f"| `{v}` | {kind.upper() if kind == 'p3f' else 'vectorless'} | {corner} | "
                      f"{p.get('dynamic', '?')} | {p.get('static', '?')} | {p.get('total', '?')} | "
                      f"{p.get('confidence', '?')} | {dut} | {top} |")
    print()
    print("P3F typical dynamic breakdown (W):")
    print()
    print("| Variant | Clocks | CLB Logic | Signals | DSP | I/O |")
    print("| :-- | --: | --: | --: | --: | --: |")
    for v in variants:
        p = power(root / v, "p3f", "typical")
        print(f"| `{v}` | {p.get('Clocks', '?')} | {p.get('CLB Logic', '?')} | {p.get('Signals', '?')} | "
              f"{p.get('DSPs', '?')} | {p.get('I/O', '?')} |")


if __name__ == "__main__":
    main()
