#!/usr/bin/env python3
"""Validate STREAM output and summarize repeated runs of one workload."""

import argparse
import json
import math
from pathlib import Path
import re
import statistics


KERNELS = ("Copy", "Scale", "Add", "Triad")


def parse_cpu_list(value):
    cpus = []
    for part in value.split(","):
        if not re.fullmatch(r"\d+(?:-\d+)?", part):
            raise ValueError("CPU list must contain comma-separated IDs or ascending ranges")
        ends = [int(item) for item in part.split("-")]
        first, last = ends[0], ends[-1]
        if not 0 <= first <= last <= 175:
            raise ValueError("CPU IDs must be within 0-175")
        cpus.extend(range(first, last + 1))
    if len(set(cpus)) != len(cpus):
        raise ValueError("Duplicate CPUs in CPU list")
    return cpus


def parse_log(text, expected_cpus=None):
    expected_cpus = list(range(176)) if expected_cpus is None else expected_cpus
    if not expected_cpus or len(set(expected_cpus)) != len(expected_cpus):
        raise ValueError("Expected CPU list must be nonempty and unique")
    threads = len(expected_cpus)
    def number(pattern):
        matches = re.findall(pattern, text)
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one workload field: {pattern}")
        return int(matches[0])

    if "Solution Validates:" not in text or re.search(r"Failed Validation", text, re.I):
        raise ValueError("Missing successful validation or explicit validation failure")
    if re.search(r"\b(?:nan|inf(?:inity)?)\b", text, re.I):
        raise ValueError("Non-finite value in STREAM output")
    if not re.search(r"Function\s+Best Rate MB/s\s+Avg time\s+Min time\s+Max time", text):
        raise ValueError("Unsupported rate units or timing columns")
    workload = {
        "array_elements": number(r"Array size\s*=\s*(\d+)\s*\(elements\)"),
        "element_bytes": number(r"This system uses\s+(\d+)\s+bytes per array element"),
        "ntimes": number(r"Each kernel will be executed\s+(\d+)\s+times"),
        "threads_requested": number(r"Number of Threads requested\s*=\s*(\d+)"),
        "threads_counted": number(r"Number of Threads counted\s*=\s*(\d+)"),
        "cpu_ids": sorted(expected_cpus),
    }
    if (workload["threads_requested"] != threads or workload["threads_counted"] != threads
            or workload["element_bytes"] != 8 or workload["ntimes"] < 2
            or workload["array_elements"] < 1):
        raise ValueError("Wrong thread count, precision, array size or iteration count")
    bindings = re.findall(r"thread\s+(\d+)\s+bound to OS proc set\s+\{([^}]+)\}", text)
    effective = {}
    for thread, cpus in bindings:
        if not cpus.strip().isdigit():
            raise ValueError("A thread is not bound to exactly one CPU")
        tid, cpu = int(thread), int(cpus)
        if tid in effective and effective[tid] != cpu:
            raise ValueError("Thread affinity changed during the run")
        effective[tid] = cpu
    if set(effective) != set(range(threads)) or set(effective.values()) != set(expected_cpus):
        raise ValueError("Missing verified one-thread-per-CPU affinity for the expected CPUs")
    rates = {}
    average_rates = {}
    times = {}
    for kernel in KERNELS:
        rows = re.findall(rf"^{kernel}:\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*$", text, re.M)
        if len(rows) != 1:
            raise ValueError(f"Missing or duplicate {kernel} result")
        rate, average, minimum, maximum = map(float, rows[0])
        if not all(math.isfinite(v) and v > 0 for v in (rate, average, minimum, maximum)):
            raise ValueError(f"Invalid {kernel} rate or time")
        if not minimum <= average <= maximum:
            raise ValueError(f"Inconsistent {kernel} timing order")
        rates[kernel] = rate
        byte_count = workload["array_elements"] * workload["element_bytes"]
        byte_count *= 2 if kernel in ("Copy", "Scale") else 3
        average_rates[kernel] = byte_count / average / 1e6
        times[kernel] = {"average": average, "minimum": minimum, "maximum": maximum}
    return {"workload": workload, "best_rate_MB_s": rates, "validation": "PASS",
            "affinity": "PASS", "average_rate_MB_s": average_rates, "times_seconds": times}


def summarize(records):
    if not records:
        raise ValueError("No STREAM records")
    if any(record["workload"] != records[0]["workload"] for record in records):
        raise ValueError("Workload dimensions differ; do not aggregate unlike runs")
    groups = {}
    for rate_key in ("best_rate_MB_s", "average_rate_MB_s"):
        metrics = {}
        for kernel in KERNELS:
            values = [record[rate_key][kernel] for record in records]
            median = statistics.median(values)
            metrics[kernel] = {
                "median_MB_s": median,
                "min_MB_s": min(values),
                "max_MB_s": max(values),
                "range_percent_of_median": 100 * (max(values) - min(values)) / median,
            }
        groups[rate_key] = metrics
    return {"workload": records[0]["workload"], "repetitions": len(records),
            "metrics": groups["best_rate_MB_s"],
            "average_rate_metrics": groups["average_rate_MB_s"], "runs": records,
            "scope": "Tuned STREAM variants; not a certification of STREAM run-rule compliance"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", type=Path)
    parser.add_argument("--expected-cpus", default="0-175",
                        help="Expected singleton CPU bindings, e.g. 0-3,44-47")
    parser.add_argument("--expected-array-elements", type=int)
    parser.add_argument("--expected-ntimes", type=int)
    args = parser.parse_args()
    try:
        records = []
        for path in args.logs:
            record = parse_log(path.read_text(), parse_cpu_list(args.expected_cpus))
            for key, expected in (("array_elements", args.expected_array_elements),
                                  ("ntimes", args.expected_ntimes)):
                if expected is not None and record["workload"][key] != expected:
                    raise ValueError(f"Unexpected {key}: require {expected}")
            record["log"] = str(path)
            records.append(record)
        print(json.dumps(summarize(records), indent=2, allow_nan=False))
    except (OSError, ValueError) as exc:
        parser.exit(1, f"ERROR: {exc}\n")


if __name__ == "__main__":
    main()
