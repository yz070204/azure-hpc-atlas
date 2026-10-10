#!/usr/bin/env python3
"""Summarize one or more STREAM runs: per-kernel bandwidth, spread, affinity.

Reads STREAM logs, checks each one self-validated and was pinned 1:1 to CPUs,
and reports Copy/Scale/Add/Triad bandwidth (median, min, max, range) across
runs so no single peak run gets cherry-picked. Prints JSON.

Requires the log to contain OMP affinity lines, i.e. the run set
OMP_DISPLAY_AFFINITY=true and captured stderr (see run-stream.sh).
"""

import argparse
import json
import math
import re
import statistics
from pathlib import Path

KERNELS = ("Copy", "Scale", "Add", "Triad")


# Fields that must match before runs may be aggregated together.
def workload_of(record):
  return {k: record[k] for k in ("array_elements", "element_bytes", "ntimes", "threads", "cpu_ids")}


# Confirm the run pinned threads to `threads` distinct CPUs (not floating or
# oversubscribed at the guest level). Doesn't detect hypervisor core mapping —
# use lscpu / the topology check for that.
def check_affinity(text, threads):
  bindings = re.findall(r"thread (\d+) bound to OS proc set\s+\{([^}]*)\}", text)
  if not bindings:
    raise ValueError("no affinity lines found "
                     "(need OMP_DISPLAY_AFFINITY=true and stderr captured)")
  by_thread = {}
  for thread, cpu in bindings:
    if not cpu.isdigit():
      raise ValueError(f"thread {thread} is not pinned to one CPU: {cpu}")
    thread, cpu = int(thread), int(cpu)
    if thread in by_thread and by_thread[thread] != cpu:
      raise ValueError(f"thread {thread} changed CPU binding")
    by_thread[thread] = cpu
  distinct = set(by_thread.values())
  if len(by_thread) != threads or len(distinct) != threads:
    raise ValueError(f"expected {threads} distinct pinned threads/CPUs, "
                     f"saw {len(by_thread)} threads on {len(distinct)} CPUs")
  return sorted(distinct)


def parse_cpu_list(value):
  cpus = set()
  for group in value.replace(" ", ",").split(","):
    if not re.fullmatch(r"\d+(?:-\d+)?", group):
      raise ValueError(f"invalid CPU list: {value}")
    ends = [int(c) for c in group.split("-")]
    first, last = ends[0], ends[-1]
    if first > last:
      raise ValueError(f"invalid CPU range: {group}")
    cpus.update(range(first, last + 1))
  return sorted(cpus)


# Parse one log into workload params, best rate, and avg-time-derived rate.
def parse_log(text):
  if "Solution Validates" not in text or re.search(r"Failed Validation", text, re.I):
    raise ValueError("STREAM did not report a successful validation")

  def field(pattern):
    match = re.search(pattern, text)
    if not match:
      raise ValueError(f"could not find field: {pattern}")
    return int(match.group(1))

  array_elements = field(r"Array size\s*=\s*(\d+)\s*\(elements\)")
  element_bytes = field(r"This system uses\s+(\d+)\s+bytes per array element")
  ntimes = field(r"Each kernel will be executed\s+(\d+)\s+times")
  threads = field(r"Number of Threads counted\s*=\s*(\d+)")
  if min(array_elements, element_bytes, ntimes, threads) <= 0 or ntimes < 2:
    raise ValueError("invalid STREAM workload parameters")
  cpu_ids = check_affinity(text, threads)
  best = {}
  average = {}
  for kernel in KERNELS:
    # Row columns: Best Rate MB/s, Avg time, Min time, Max time.
    match = re.search(rf"^{kernel}:\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*$", text, re.M)
    if not match:
      raise ValueError(f"missing {kernel} result row")
    rate, avg_time, _min_time, _max_time = map(float, match.groups())
    if not all(math.isfinite(v) and v > 0 for v in (rate, avg_time, _min_time, _max_time)):
      raise ValueError(f"invalid {kernel} rate or timing")
    words = 2 if kernel in ("Copy", "Scale") else 3  # arrays moved per element
    moved_bytes = array_elements * element_bytes * words
    best[kernel] = rate                              # STREAM's own peak (min time)
    average[kernel] = moved_bytes / avg_time / 1e6   # sustained (avg time)

  return {
      "array_elements": array_elements,
      "element_bytes": element_bytes,
      "ntimes": ntimes,
      "threads": threads,
      "cpu_ids": cpu_ids,
      "best_rate_MB_s": best,
      "average_rate_MB_s": average,
  }


# Median/min/max/spread of one rate metric across all runs.
def spread(records, rate_key):
  out = {}
  for kernel in KERNELS:
    values = [r[rate_key][kernel] for r in records]
    median = statistics.median(values)
    out[kernel] = {
        "median_MB_s": round(median, 1),
        "min_MB_s": round(min(values), 1),
        "max_MB_s": round(max(values), 1),
        "range_pct_of_median": round(100 * (max(values) - min(values)) / median, 1),
    }
  return out


def summarize(records):
  if not records:
    raise ValueError("no STREAM runs to summarize")
  workload = workload_of(records[0])
  if any(workload_of(r) != workload for r in records):
    raise ValueError("runs differ in array size / element type / ntimes / threads / CPU placement; refusing to aggregate")
  return {
      "workload": workload,
      "repetitions": len(records),
      "validation": "PASS",   # parse_log raises otherwise
      "affinity": "PASS",     # parse_log raises otherwise
      "best_rate_metrics": spread(records, "best_rate_MB_s"),
      "average_rate_metrics": spread(records, "average_rate_MB_s"),
      "runs": records,
  }


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("logs", nargs="+", type=Path, help="STREAM log file(s)")
  parser.add_argument("--expected-threads", type=int, help="required effective thread count")
  parser.add_argument("--expected-cpus", help="required effective CPU IDs (list/ranges)")
  args = parser.parse_args()

  try:
    expected_cpus = parse_cpu_list(args.expected_cpus) if args.expected_cpus is not None else None
    records = []
    for path in args.logs:
      record = parse_log(path.read_text())
      if args.expected_threads is not None and record["threads"] != args.expected_threads:
        raise ValueError(f"{path}: expected {args.expected_threads} threads, saw {record['threads']}")
      if expected_cpus is not None and record["cpu_ids"] != expected_cpus:
        raise ValueError(f"{path}: effective CPU placement differs from requested CPU list")
      record["log"] = str(path)
      records.append(record)
    print(json.dumps(summarize(records), indent=2))
  except (OSError, ValueError) as exc:
    parser.exit(1, f"ERROR: {exc}\n")


if __name__ == "__main__":
  main()
