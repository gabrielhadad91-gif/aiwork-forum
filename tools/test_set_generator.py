#!/usr/bin/env python3
"""
test_set_generator.py
AIWORK.ONLINE rubric v1.0 — trading_signals_xauusd

Generate a deterministic, seeded test set for the trading_signals_xauusd
audit. Reproducible by anyone with the seed + this script + the historical
data archive.

STATUS: SKELETON (Week 1)
  - Real classify_regime() with ADX in Week 3
  - Real load_bars() from public archive in Week 2 (after Gabriel provides
    the data source URL)
  - Per-case test set is generated from real historical M5 bars for
    2024 XAU/USD

USAGE (after Week 2/3 implementation):
    python tools/test_set_generator.py --seed <UUID> --output /tmp/audit_seed.json

SPEC: /spec Section 4
"""

import argparse
import hashlib
import json
import random
from datetime import datetime, timedelta
from pathlib import Path

# -----------------------------------------------------------------------------
# CONSTANTS (must match rubric YAML)
# -----------------------------------------------------------------------------

# Public archive location — must be published for reproducibility
# WEEK 2: Gabriel provides the source URL; update this to the public
# parquet file at /data/xauusd_m5_2024.parquet
DATA_ARCHIVE = "https://aiwork.online/data/xauusd_m5_2024.parquet"

DISTRIBUTION = {
    "trending": 0.40,
    "ranging": 0.40,
    "transition": 0.20,
}

CASES_PER_AUDIT = 60
BARS_PER_CASE = 100
FORWARD_HORIZON_BARS = 12


# -----------------------------------------------------------------------------
# STUB FUNCTIONS — to be implemented in Week 3
# -----------------------------------------------------------------------------

def classify_regime(bars: list[dict]) -> str:
    """
    Regime tag is a label for SCORING only. The agent never sees it.
    Trending: ADX > 25, low std/mean ratio
    Ranging: ADX < 20, high std/mean ratio on detrended
    Transition: change in ADX > 10 over the window

    WEEK 3: Implement with real ADX (Average Directional Index) using
    pandas + numpy. Stub returns uniform random for skeleton testing.
    """
    # STUB: random classification for skeleton — REPLACE IN WEEK 3
    return random.choice(list(DISTRIBUTION.keys()))


def load_bars(start: datetime, count: int) -> list[dict]:
    """
    Load M5 bars from the public archive. Cached locally.

    WEEK 2: Real implementation after Gabriel provides data source.
    Expected schema per bar:
        { "timestamp": "2024-01-15T08:00:00Z",
          "open": 2050.10, "high": 2050.80, "low": 2049.50, "close": 2050.30,
          "volume": 1234 }
    """
    # STUB: returns synthetic bars for skeleton testing — REPLACE IN WEEK 2
    return [
        {
            "timestamp": (start + timedelta(minutes=5 * i)).isoformat() + "Z",
            "open": 2000.0, "high": 2001.0, "low": 1999.0, "close": 2000.5,
            "volume": 1000,
        }
        for i in range(count)
    ]


# -----------------------------------------------------------------------------
# MAIN GENERATION LOGIC
# -----------------------------------------------------------------------------

def generate_test_set(seed: str, output_path: Path) -> dict:
    """
    Generate the full test set deterministically from the seed.

    Algorithm:
      1. Seed an RNG with the audit seed.
      2. Pick random start dates from 2024 (oversample to allow filtering).
      3. For each start, load bars and classify regime on the FULL window
         (input + forward).
      4. Accept cases until per-regime targets are met.
      5. Sort by decision_bar timestamp, re-index.
      6. Write artifact JSON; SHA256 the output for cert binding.
    """
    rng = random.Random(seed)

    # Pick N random start dates from 2024
    start_dates = []
    base = datetime(2024, 1, 1)
    days_in_2024 = 365
    for _ in range(CASES_PER_AUDIT * 2):  # oversample, filter later
        offset = timedelta(days=rng.randint(0, days_in_2024 - 1))
        start_dates.append(base + offset)
    start_dates = sorted(set(start_dates))[:CASES_PER_AUDIT * 2]

    cases = []
    per_regime_target = {
        regime: int(CASES_PER_AUDIT * frac)
        for regime, frac in DISTRIBUTION.items()
    }
    per_regime_count = {regime: 0 for regime in DISTRIBUTION}

    for start in start_dates:
        bars = load_bars(start, BARS_PER_CASE + FORWARD_HORIZON_BARS)
        if len(bars) < BARS_PER_CASE + FORWARD_HORIZON_BARS:
            continue

        # Split into input bars (visible to agent) and forward bars (scored)
        input_bars = bars[:BARS_PER_CASE]
        forward_bars = bars[BARS_PER_CASE:]

        # Classify regime on the FULL window (input + forward) for scoring
        regime = classify_regime(input_bars + forward_bars)

        if per_regime_count[regime] >= per_regime_target[regime]:
            continue

        cases.append({
            "case_index": len(cases),
            "regime": regime,
            "input_bars": input_bars,
            "forward_bars": forward_bars,
            "decision_bar": input_bars[-1],
        })
        per_regime_count[regime] += 1

        if all(per_regime_count[r] >= per_regime_target[r] for r in DISTRIBUTION):
            break

    # Sort and re-index
    cases.sort(key=lambda c: c["decision_bar"]["timestamp"])
    for i, c in enumerate(cases):
        c["case_index"] = i

    artifact = {
        "schema_version": "0.1",
        "seed": seed,
        "generated_at": datetime.utcnow().isoformat(),
        "cases": cases,
        "metadata": {
            "rubric_id": "trading_signals_xauusd",
            "rubric_version": "1.0",
            "cases_per_audit": CASES_PER_AUDIT,
            "distribution": DISTRIBUTION,
            "actual_per_regime": per_regime_count,
        },
    }

    output_path.write_text(json.dumps(artifact, indent=2))
    return artifact


def main():
    p = argparse.ArgumentParser(description="AIWORK.ONLINE test set generator (skeleton)")
    p.add_argument("--seed", required=True,
                   help="Deterministic seed (use a UUID per audit)")
    p.add_argument("--output", required=True, type=Path)
    args = p.parse_args()

    artifact = generate_test_set(args.seed, args.output)
    digest = hashlib.sha256(args.output.read_bytes()).hexdigest()
    print(f"Generated {len(artifact['cases'])} cases")
    print(f"Per-regime: {artifact['metadata']['actual_per_regime']}")
    print(f"SHA256: {digest}")
    print(f"Test set hash (for cert): {digest}")
    print()
    print("WARNING: SKELETON — load_bars() returns synthetic data.")
    print("         Real implementation lands in Week 2/3.")


if __name__ == "__main__":
    main()
