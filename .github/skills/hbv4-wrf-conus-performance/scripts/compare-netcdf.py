#!/usr/bin/env python3
import math
import sys

import numpy as np
from netCDF4 import Dataset


VARIABLES = ("U", "V", "W", "T", "PH", "QVAPOR", "TSLB", "MU", "TSK", "RAINC", "RAINNC")
MAX_CHUNK_ELEMENTS = 16_000_000


def chunks(shape):
    axis = next((i for i, size in enumerate(shape) if size > 1), 0)
    trailing = math.prod(shape[axis + 1 :])
    step = max(1, MAX_CHUNK_ELEMENTS // max(1, trailing))
    for start in range(0, shape[axis], step):
        selection = [slice(None)] * len(shape)
        selection[axis] = slice(start, min(start + step, shape[axis]))
        yield tuple(selection)


def main():
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} REFERENCE.nc CANDIDATE.nc")

    with Dataset(sys.argv[1]) as reference, Dataset(sys.argv[2]) as candidate:
        print("variable,min,max,mean,stddev,count")
        for name in VARIABLES:
            if name not in reference.variables or name not in candidate.variables:
                raise SystemExit(f"required variable missing: {name}")
            left = reference.variables[name]
            right = candidate.variables[name]
            if left.shape != right.shape:
                raise SystemExit(
                    f"shape mismatch for {name}: reference={left.shape}, candidate={right.shape}"
                )

            count = 0
            total = 0.0
            total_squared = 0.0
            minimum = math.inf
            maximum = -math.inf
            for selection in chunks(left.shape):
                difference = np.ma.asarray(right[selection] - left[selection]).compressed()
                if not np.isfinite(difference).all():
                    raise SystemExit(f"non-finite difference found for {name}")
                values = difference.astype(np.float64, copy=False)
                count += values.size
                total += float(values.sum(dtype=np.float64))
                total_squared += float(np.square(values).sum(dtype=np.float64))
                if values.size:
                    minimum = min(minimum, float(values.min()))
                    maximum = max(maximum, float(values.max()))

            mean = total / count
            variance = max(0.0, total_squared / count - mean * mean)
            print(
                f"{name},{minimum:.9g},{maximum:.9g},{mean:.9g},"
                f"{math.sqrt(variance):.9g},{count}"
            )


if __name__ == "__main__":
    main()
