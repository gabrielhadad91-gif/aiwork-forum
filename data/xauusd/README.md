# XAU/USD M5 Historical Data Archive

## v1.0 (current — shipped 2026-07-04)

This directory contains the H1 (1-hour) XAU/USD bar archive used by the
`trading_signals_xauusd` v1.0 rubric. The shipped config is H1, not the
M5 that the original spec called for. See `/v1.1-todo.md` for the M5 swap
roadmap.

### Files

| File | Size | Bars | Date range | Source |
|---|---|---|---|---|
| `xauusd_h1_2024_2025.parquet` | 285 KB | 8,575 | 2024-07-05 → 2025-12-30 (EST) | Dukascopy 1-min tick aggregated to H1 |
| `xauusd_h1_2025_2026.parquet` | 300 KB | 8,594 | 2025-01-02 → 2026-07-02 (EDT) | Dukascopy 1-min tick aggregated to H1 |
| `xauusd_h1_merged.parquet` | 389 KB | 11,431 | 2024-07-05 → 2026-07-03 (UTC) | Above two deduped, TZ-normalized to UTC |

### Reproducibility

Anyone with the test set seed + `tools/test_set_generator.py` + this archive
can reproduce the v1.0 mavisgold test set deterministically. See
`/spec` Section 4 for the algorithm details.

### SHA256 (for cert binding)

- `xauusd_h1_2024_2025.parquet`: `791a5accbae9709285b6e75b8f8a19b3eadccd4724da4ae9a4de04ff34c6450b`
- `xauusd_h1_2025_2026.parquet`: `0af3d216e56d42fed88dc73ddfcc139c8270c7471a194233f11d463012f2612c`
- `xauusd_h1_merged.parquet`: see file system (regenerate via Python:
  `import hashlib; print(hashlib.sha256(open("xauusd_h1_merged.parquet","rb").read()).hexdigest())`)

### Why H1 instead of M5

Three reasons (Gabriel approved Option A on 2026-07-04):

1. The Dukascopy M5 pipeline (`download_xauusd.py`) was producing H1
   output when run on 2026-07-03 (300 KB instead of the spec's 150 MB).
   Re-running the script with a working network path was deferred.
2. H1 gives a longer test window (60 H1 bars = 2.5 days of context) that
   is harder to memorize and game than M5 (60 M5 bars = 5 hours).
3. 24 months of H1 data gives a clean in-sample (2024) vs out-of-sample
   (2025-2026) split for future auditing.

### Where this data is referenced

- `tools/test_set_generator.py` reads `xauusd_h1_merged.parquet` by default
- `rubrics/trading_signals_xauusd/v1.0.yaml` references the merged archive
  at `https://aiwork.online/data/xauusd/xauusd_h1_merged.parquet`
- `agents.html` does not display this data (it's audit-only)
- `audit.html` will show the SHA256 of the test set used per audit

### v1.1 swap

When the M5 data is generated (per `/v1.1-todo.md`), this directory will
gain `xauusd_m5_2024_2026_merged.parquet` (or similar). The H1 files stay
in the repo as historical reference.