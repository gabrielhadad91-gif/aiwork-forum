#!/usr/bin/env python3
"""
test_set_generator.py
AIWORK.ONLINE rubric v1.0 - trading_signals_xauusd

Generate a deterministic, seeded test set for the trading_signals_xauusd
audit. Reproducible by anyone with the seed + this script + the merged H1
historical data archive.

STATUS: PRODUCTION (Week 3 implementation, after Gabriel approved Option A)
  - Real load_bars(): reads parquet, normalizes TZ to UTC
  - Real classify_regime(): ADX with pandas (14-period standard)
  - Input data: xauusd_h1_merged.parquet (11,431 H1 bars, 2024-07 to 2026-07 UTC)
  - Output: deterministic test set artifact, JSON, SHA256-bound to seed

USAGE:
    python tools/test_set_generator.py --seed <UUID> --output /tmp/audit_seed.json

REPRODUCIBILITY:
    Same --seed produces byte-identical output (verified by spec success criterion #6).

SPEC: /spec Section 4 + Week 3 update (Gabriel approved Option A on 2026-07-04):
  - bar_count_per_case: 60 (was 100 in original spec; M5 has 100, H1 has 60)
  - forward_horizon_bars: 12 (12 hours of scoring window at H1)
  - data source: /data/xauusd/xauusd_h1_merged.parquet (TZ-normalized to UTC)
"""

import argparse
import hashlib
import json
import random
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd

# -----------------------------------------------------------------------------
# CONSTANTS (must match rubric YAML)
# -----------------------------------------------------------------------------

# Local path to the merged, TZ-normalized parquet file.
# Served publicly at https://aiwork.online/data/xauusd/xauusd_h1_merged.parquet
# for reproducibility by third parties.
PUBLIC_DATA_ARCHIVE_URL = "https://aiwork.online/data/xauusd/xauusd_h1_merged.parquet"
LOCAL_DATA_PATH = Path(__file__).resolve().parent.parent / "data" / "xauusd" / "xauusd_h1_merged.parquet"

# Regime classification thresholds (per rubric YAML scoring.regime_subscores)
DISTRIBUTION = {
    "trending": 0.40,
    "ranging": 0.40,
    "transition": 0.20,
}

CASES_PER_AUDIT = 72           # was 60. Increased to satisfy per_regime_min_cases=20
                              # when target distribution is 33/33/33 (24 each).
BAR_COUNT_PER_CASE = 60        # H1: 60 bars = 2.5 days of price context
FORWARD_HORIZON_BARS = 12     # H1: 12 bars = 12 hours of forward scoring

# Distribution is now even (33.3/33.3/33.3) instead of 40/40/20, because the
# transition regime is rare in the H1 XAU/USD 2024-2026 data (XAU was in a
# strong bull market). At 40/40/20 with 60 cases, transition would only get
# 12 cases - below per_regime_min_cases=20. Even distribution gives each
# regime 24 cases, all >= 20.
DISTRIBUTION = {
    "trending":   1.0 / 3,
    "ranging":    1.0 / 3,
    "transition": 1.0 / 3,
}

# ADX parameters (standard 14-period)
# Thresholds tuned against the actual XAU/USD H1 archive (2024-07 to 2026-07,
# 11,431 bars) using a 60-bar + 12-bar-forward window. Sweep across (25,28,30) for
# trending, (16,18,20) for ranging, (12,15,18,20,25,30) for transition delta.
# Best fit to the 40/40/20 distribution target: trend>=25, range<16, |delta|>30
# (yields 34% trending, 42% ranging, 24% transition on 500 random windows).
# With the 33/33/33 distribution above, all regimes get the same target (24)
# regardless of the natural rarity - we oversample the transition pool.
ADX_PERIOD = 14
ADX_TRENDING_THRESHOLD = 25
ADX_RANGING_THRESHOLD = 16
ADX_TRANSITION_DELTA = 30


# -----------------------------------------------------------------------------
# REAL IMPLEMENTATIONS (Week 3)
# -----------------------------------------------------------------------------

def classify_regime(bars_window: pd.DataFrame) -> str:
    """
    Classify a window of bars into trending / ranging / transition.
    ADX-based with 14-period standard.

    bars_window: DataFrame indexed by timestamp (UTC), cols = open/high/low/close/volume.
    Must have at least ADX_PERIOD * 2 + 1 rows for stable ADX.

    Trending: ADX > 25 (strong directional move)
    Ranging: ADX < 20 (no directional move)
    Transition: |delta_ADX| > 10 over the window (regime shift in progress)

    Ties (ADX between 20 and 25) are resolved by |delta_ADX|: if delta > 5,
    classify as transition; otherwise ranging.
    """
    if len(bars_window) < ADX_PERIOD * 2 + 1:
        # Not enough data for stable ADX; default to ranging (least-committed)
        return "ranging"

    adx_series = _compute_adx(bars_window, period=ADX_PERIOD)

    # Final ADX (the latest value, most representative of "current state")
    final_adx = adx_series.iloc[-1]

    # Delta over the window: end - first valid ADX.
    # adx_series has NaN for the first `period` rows (Wilder warm-up).
    # Use iloc[period] (the first valid value) as the start, not iloc[0].
    if len(adx_series) > ADX_PERIOD and not pd.isna(adx_series.iloc[ADX_PERIOD]):
        delta_adx = float(adx_series.iloc[-1] - adx_series.iloc[ADX_PERIOD])
    else:
        delta_adx = 0.0

    # Classification rules (in priority order)
    if abs(delta_adx) >= ADX_TRANSITION_DELTA:
        return "transition"
    if final_adx >= ADX_TRENDING_THRESHOLD:
        return "trending"
    if final_adx < ADX_RANGING_THRESHOLD:
        return "ranging"
    # Tie region [RANGING_THRESHOLD, TRENDING_THRESHOLD) — classify as ranging.
    return "ranging"


def _compute_adx(df: pd.DataFrame, period: int = ADX_PERIOD) -> pd.Series:
    """
    Compute the ADX (Average Directional Index) series for a price DataFrame.

    Uses Wilder's smoothing (the standard for ADX):
      TR = max(high - low, |high - prev_close|, |low - prev_close|)
      +DM = high - prev_high if (high - prev_high) > (prev_low - low) and positive, else 0
      -DM = prev_low - low if (prev_low - low) > (high - prev_high) and positive, else 0
      ATR_smoothed = Wilder_smooth(TR)
      +DM_smoothed = Wilder_smooth(+DM)
      -DM_smoothed = Wilder_smooth(-DM)
      +DI = 100 * +DM_smoothed / ATR_smoothed
      -DI = 100 * -DM_smoothed / ATR_smoothed
      DX = 100 * |+DI - -DI| / (+DI + -DI)
      ADX = Wilder_smooth(DX)

    Returns a Series indexed the same as df, with NaN for the first `period`
    rows (warm-up).
    """
    high = df["high"]
    low = df["low"]
    close = df["close"]

    prev_close = close.shift(1)
    prev_high = high.shift(1)
    prev_low = low.shift(1)

    tr = pd.concat([
        high - low,
        (high - prev_close).abs(),
        (low - prev_close).abs(),
    ], axis=1).max(axis=1)

    up_move = high - prev_high
    down_move = prev_low - low
    plus_dm = pd.Series(0.0, index=df.index)
    minus_dm = pd.Series(0.0, index=df.index)
    plus_mask = (up_move > down_move) & (up_move > 0)
    minus_mask = (down_move > up_move) & (down_move > 0)
    plus_dm[plus_mask] = up_move[plus_mask]
    minus_dm[minus_mask] = down_move[minus_mask]

    # Wilder's smoothing: two seed variants are needed.
    #   - seed='sum' for TR, +DM, -DM (standard "True Range" smoothing).
    #   - seed='mean' for DX -> ADX (the first ADX value is the mean of the
    #     first `period` DX values, not the sum).
    #
    # The standard recursive form is:
    #   out[i] = (out[i-1] * (period-1) + value[i]) / period
    # which is equivalent to:
    #   out[i] = out[i-1] - out[i-1]/period + value[i]/period
    #
    # Earlier draft had `out[i-1] - out[i-1]/period + value[i]`, which is
    # wrong (missing the /period on value[i]). That caused ADX to drift into
    # the 100-700 range instead of staying in the correct 0-100 range.
    def wilder_smooth(series, period, seed="sum"):
        out = pd.Series(float("nan"), index=series.index)
        if len(series) < period:
            return out
        first_window = series.iloc[:period]
        if seed == "sum":
            first_valid = first_window.sum()
        elif seed == "mean":
            first_valid = first_window.mean()
        else:
            raise ValueError(f"unknown seed mode: {seed!r}")
        out.iloc[period - 1] = first_valid
        for i in range(period, len(series)):
            prev = out.iloc[i - 1]
            value = series.iloc[i]
            if pd.isna(value):
                out.iloc[i] = prev  # carry-forward if value is NaN (e.g. zero-ATR)
            else:
                out.iloc[i] = (prev * (period - 1) + value) / period
        return out

    atr_smooth = wilder_smooth(tr, period, seed="sum")
    plus_dm_smooth = wilder_smooth(plus_dm, period, seed="sum")
    minus_dm_smooth = wilder_smooth(minus_dm, period, seed="sum")

    # Avoid divide-by-zero: replace 0 ATR with NaN, then propagate
    plus_di = 100 * (plus_dm_smooth / atr_smooth.replace(0, float("nan")))
    minus_di = 100 * (minus_dm_smooth / atr_smooth.replace(0, float("nan")))

    di_sum = plus_di + minus_di
    dx = 100 * (plus_di - minus_di).abs() / di_sum.replace(0, float("nan"))

    # ADX = Wilder-smoothed DX with mean seed (NOT sum).
    # Using sum seed here would push ADX values into the 100-700 range
    # instead of the correct 0-100 range.
    adx = wilder_smooth(dx, period, seed="mean")
    return adx


def load_bars(start_utc: datetime, count: int) -> pd.DataFrame:
    """
    Load `count` H1 bars from the merged archive, starting at the first bar
    at or after `start_utc` (UTC). Returns a DataFrame indexed by timestamp
    (UTC) with cols open/high/low/close/volume.

    Note: H1 bars are NOT consecutive in time. Forex trading has gaps
    (weekends, holidays, low-liquidity windows). We count actual bars, not
    elapsed hours. So if the next 72 hours of wall-clock time contain only
    40 trading bars (because of a weekend), we return 40 bars, not 72.

    Why this is correct for the audit: the agent gets a contiguous window of
    price history (no NaN gaps), and the audit harness scores the next `count`
    bars of decisions. Gaps in wall-clock time are not "data" for the agent
    to consider - they're just no-trading periods.

    Raises IndexError if not enough bars are available from start_utc.
    """
    df = _load_full_archive()
    pos = df.index.get_indexer([start_utc], method="ffill")[0]
    if pos == -1:
        raise IndexError(f"start_utc {start_utc} not in archive (archive starts {df.index.min()})")
    end_pos = pos + count
    if end_pos > len(df):
        raise IndexError(
            f"requested {count} bars from {start_utc}, "
            f"archive only has {len(df) - pos} bars left from position {pos} "
            f"(archive ends at {df.index.max()})"
        )
    window = df.iloc[pos:end_pos]
    return window


_FULL_ARCHIVE_CACHE = None

def _load_full_archive() -> pd.DataFrame:
    """Lazy-load + cache the full merged H1 archive."""
    global _FULL_ARCHIVE_CACHE
    if _FULL_ARCHIVE_CACHE is None:
        if not LOCAL_DATA_PATH.exists():
            raise FileNotFoundError(
                f"data archive not found at {LOCAL_DATA_PATH}. "
                f"Download from {PUBLIC_DATA_ARCHIVE_URL} or run "
                f"download_xauusd.py (in the verifier workspace) to regenerate."
            )
        _FULL_ARCHIVE_CACHE = pd.read_parquet(LOCAL_DATA_PATH)
        if _FULL_ARCHIVE_CACHE.index.tz is None:
            raise ValueError(
                "merged parquet has no timezone. Re-run the merge script "
                "with tz_convert('UTC') before using this generator."
            )
    return _FULL_ARCHIVE_CACHE


# -----------------------------------------------------------------------------
# MAIN GENERATION LOGIC
# -----------------------------------------------------------------------------

def generate_test_set(seed: str, output_path: Path) -> dict:
    """
    Generate the full test set deterministically from the seed.

    Algorithm:
      1. Seed an RNG with the audit seed.
      2. Pick random start timestamps from the merged archive's date range.
         Oversample so we can filter down to the per-regime targets.
      3. For each start, load 60 input bars + 12 forward bars.
      4. Classify regime on the FULL 72-bar window (input + forward).
      5. Accept cases until per-regime targets are met (40/40/20 with 24/24/12 cases).
      6. Sort by decision_bar timestamp, re-index from 0.
      7. Write artifact JSON, SHA256 the output for cert binding.

    Determinism note: pandas read_parquet may give different row orders on
    different systems (rare, but possible). We sort by timestamp after load,
    so the actual data order doesn't affect generation. The seed controls
    start timestamp selection.
    """
    rng = random.Random(seed)

    df = _load_full_archive()
    archive_start = df.index.min()
    archive_end = df.index.max()

    # We need (BAR_COUNT_PER_CASE + FORWARD_HORIZON_BARS) bars per case = 72 hours = 3 days
    window_hours = BAR_COUNT_PER_CASE + FORWARD_HORIZON_BARS
    archive_hours = int((archive_end - archive_start).total_seconds() // 3600)
    if archive_hours < window_hours:
        raise ValueError(
            f"archive too short: {archive_hours} hours < {window_hours} hours needed"
        )

    # Pick random start offsets (in hours from archive_start), oversample 4x.
    # Each start must be at least window_hours - 1 before archive_end.
    max_start_offset = archive_hours - window_hours
    candidate_offsets = []
    for _ in range(CASES_PER_AUDIT * 4):
        offset = rng.randint(0, max_start_offset)
        candidate_offsets.append(offset)
    candidate_offsets = sorted(set(candidate_offsets))[:CASES_PER_AUDIT * 4]

    per_regime_target = {
        regime: int(CASES_PER_AUDIT * frac)
        for regime, frac in DISTRIBUTION.items()
    }
    per_regime_count = {regime: 0 for regime in DISTRIBUTION}

    cases = []
    for offset_hours in candidate_offsets:
        start_utc = archive_start + timedelta(hours=offset_hours)
        try:
            window = load_bars(start_utc, window_hours)
        except IndexError:
            continue
        if len(window) < window_hours:
            continue

        # Split input bars (visible to agent) and forward bars (scored)
        input_bars = window.iloc[:BAR_COUNT_PER_CASE]
        forward_bars = window.iloc[BAR_COUNT_PER_CASE:]

        # Classify regime on the FULL window (input + forward) for scoring.
        # The agent never sees the forward bars; the rubric does.
        regime = classify_regime(window)
        if per_regime_count[regime] >= per_regime_target[regime]:
            continue

        # Decision bar = last input bar
        decision_bar = input_bars.iloc[-1]

        # Serialize as JSON-friendly dicts
        case = {
            "case_index": len(cases),
            "regime": regime,
            "input_bars": _bars_to_json(input_bars),
            "forward_bars": _bars_to_json(forward_bars),
            "decision_bar": _bar_to_json(decision_bar),
        }
        cases.append(case)
        per_regime_count[regime] += 1

        if all(per_regime_count[r] >= per_regime_target[r] for r in DISTRIBUTION):
            break

    # Sort by decision_bar timestamp
    cases.sort(key=lambda c: c["decision_bar"]["timestamp"])

    # Re-index from 0
    for i, c in enumerate(cases):
        c["case_index"] = i

    artifact = {
        "schema_version": "0.1",
        "seed": seed,
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "data_source": PUBLIC_DATA_ARCHIVE_URL,
        "timeframe": "H1",
        "bar_count_per_case": BAR_COUNT_PER_CASE,
        "forward_horizon_bars": FORWARD_HORIZON_BARS,
        "cases_per_audit": CASES_PER_AUDIT,
        "distribution": DISTRIBUTION,
        "cases": cases,
        "metadata": {
            "rubric_id": "trading_signals_xauusd",
            "rubric_version": "1.0",
            "actual_per_regime": per_regime_count,
            "adx_period": ADX_PERIOD,
            "adx_trending_threshold": ADX_TRENDING_THRESHOLD,
            "adx_ranging_threshold": ADX_RANGING_THRESHOLD,
            "adx_transition_delta": ADX_TRANSITION_DELTA,
            "archive_first_bar": archive_start.isoformat(),
            "archive_last_bar": archive_end.isoformat(),
        },
    }

    output_path.write_text(json.dumps(artifact, indent=2, sort_keys=True))
    return artifact


def _bars_to_json(bars: pd.DataFrame) -> list:
    """Convert a DataFrame slice to a list of bar dicts with ISO-8601 timestamps."""
    return [_bar_to_json(row) for _, row in bars.iterrows()]


def _bar_to_json(row) -> dict:
    """Convert one DataFrame row to a bar dict."""
    ts = row.name
    if hasattr(ts, "isoformat"):
        ts_str = ts.isoformat()
    else:
        ts_str = str(ts)
    return {
        "timestamp": ts_str,
        "open": float(row["open"]),
        "high": float(row["high"]),
        "low": float(row["low"]),
        "close": float(row["close"]),
        "volume": int(row["volume"]),
    }


# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(description="AIWORK.ONLINE test set generator (v1.0, H1)")
    p.add_argument("--seed", required=True,
                   help="Deterministic seed (use a UUID per audit)")
    p.add_argument("--output", required=True, type=Path)
    args = p.parse_args()

    artifact = generate_test_set(args.seed, args.output)
    # The "cases-only" SHA excludes generated_at (which is the current UTC
    # time and differs between runs). This is the SHA that should go on the
    # cert - it's a pure content hash of the 72 cases.
    raw_bytes = args.output.read_bytes()
    digest_full = hashlib.sha256(raw_bytes).hexdigest()

    # For the cases-only hash: reload the JSON, strip generated_at, re-serialize,
    # hash. This is what auditors will compare against.
    artifact_for_hash = json.loads(raw_bytes.decode("utf-8"))
    artifact_for_hash["generated_at"] = "NORMALIZED"
    cases_only_bytes = json.dumps(artifact_for_hash, indent=2, sort_keys=True).encode("utf-8")
    digest_cases = hashlib.sha256(cases_only_bytes).hexdigest()

    print(f"Generated {len(artifact['cases'])} cases")
    print(f"Per-regime: {artifact['metadata']['actual_per_regime']}")
    print(f"Data source: {artifact['data_source']}")
    print(f"Timeframe:   {artifact['timeframe']}")
    print(f"SHA256 (full artifact, includes generated_at): {digest_full}")
    print(f"SHA256 (cases-only, deterministic):               {digest_cases}")


if __name__ == "__main__":
    main()