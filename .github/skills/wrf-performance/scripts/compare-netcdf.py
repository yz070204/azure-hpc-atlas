#!/usr/bin/env python3
"""Compare key fields of a WRF output file against a reference output.

For each selected variable, prints statistics of candidate - reference
(min, max, mean, stddev, count) as CSV. Reads in chunks so large CONUS
outputs fit in memory. Reports differences only; no pass/fail tolerance.

Usage: compare-netcdf.py REFERENCE.nc CANDIDATE.nc
"""

import math
import sys

import numpy as np
from netCDF4 import Dataset

# Prognostic and surface fields most sensitive to numerical changes.
VARIABLES = ("U", "V", "W", "T", "PH", "QVAPOR", "TSLB", "MU", "TSK",
             "RAINC", "RAINNC")
MAX_CHUNK_ELEMENTS = 16_000_000


def chunks(shape):
  """Yield slices along the first non-singleton axis, bounded in size."""
  axis = next((i for i, size in enumerate(shape) if size > 1), 0)
  trailing = math.prod(shape[axis + 1:])
  step = max(1, MAX_CHUNK_ELEMENTS // max(1, trailing))
  for start in range(0, shape[axis], step):
    selection = [slice(None)] * len(shape)
    selection[axis] = slice(start, min(start + step, shape[axis]))
    yield tuple(selection)


def difference_stats(reference, candidate):
  """Return (min, max, mean, stddev, count) of candidate - reference."""
  count, total, total_sq = 0, 0.0, 0.0
  low, high = math.inf, -math.inf
  for selection in chunks(reference.shape):
    diff = np.ma.asarray(candidate[selection] - reference[selection]).compressed()
    values = diff.astype(np.float64, copy=False)
    if not np.isfinite(values).all():
      raise ValueError("non-finite difference")
    if values.size:
      count += values.size
      total += float(values.sum())
      total_sq += float(np.square(values).sum())
      low = min(low, float(values.min()))
      high = max(high, float(values.max()))
  if not count:
    raise ValueError("no comparable values")
  mean = total / count
  stddev = math.sqrt(max(0.0, total_sq / count - mean * mean))
  return low, high, mean, stddev, count


def main():
  if len(sys.argv) != 3:
    sys.exit(f"usage: {sys.argv[0]} REFERENCE.nc CANDIDATE.nc")

  with Dataset(sys.argv[1]) as ref, Dataset(sys.argv[2]) as cand:
    print("variable,min,max,mean,stddev,count")
    for name in VARIABLES:
      if name not in ref.variables or name not in cand.variables:
        sys.exit(f"ERROR: variable missing: {name}")
      left, right = ref.variables[name], cand.variables[name]
      if left.shape != right.shape:
        sys.exit(f"ERROR: shape mismatch for {name}: {left.shape} vs {right.shape}")
      try:
        low, high, mean, stddev, count = difference_stats(left, right)
      except ValueError as exc:
        sys.exit(f"ERROR: {name}: {exc}")
      print(f"{name},{low:.9g},{high:.9g},{mean:.9g},{stddev:.9g},{count}")


if __name__ == "__main__":
  main()
