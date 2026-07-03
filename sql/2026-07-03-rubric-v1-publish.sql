-- =============================================================================
-- AIWORK.ONLINE v1.0 Rubric -- Week 2 Publish (idempotent)
-- Date: 2026-07-03 (revised 2026-07-03 19:28 AEST)
-- Builder: gambuu
-- Reviewer: Gabriel
-- =============================================================================
-- WHAT THIS SCRIPT DOES
--   INSERTs (or UPDATEs if already present) one row into rubric_skills
--   (status='published') for the trading_signals_xauusd v1.0 rubric.
--   Makes the homepage "Published Rubrics" stat show 1.
--
-- WHY IDEMPOTENT VERSION
--   The first run (2026-07-03 19:00 AEST) succeeded but the operator
--   re-ran the script and hit "duplicate key value violates unique
--   constraint" on the (id) primary key. The UPSERT below is safe
--   to re-run any number of times.
--
-- EXECUTION
--   Run in Supabase SQL editor. Single transaction. The YAML content
--   is inlined below (escaped: ' became ''). Same bytes as the file at
--   /rubrics/trading_signals_xauusd/v1.0.yaml.
-- =============================================================================

BEGIN;

INSERT INTO rubric_skills (
  id, family, display_name, short_description, version, effective_from,
  superseded_by, status, rubric_yaml, created_at
) VALUES (
  'trading_signals_xauusd',
  'trading',
  'XAU/USD Gold Trading Signal Generation',
  'Generates BUY/SELL/HOLD signals for XAU/USD with entry, stop-loss, take-profit, confidence, and reasoning. Tested against sealed historical price scenarios.',
  '1.0',
  DATE '2026-08-01',
  NULL,
  'published',
  '---
# AIWORK.ONLINE Rubric v1.0
# Skill: trading_signals_xauusd
# Effective from: 2026-08-01
# Author: AIWORK Certification Authority
# Status: PUBLISHED 2026-07-03 (Week 2 ship)
# Spec: C:\Users\Gabri\.mavis\agents\verifier\workspace\aiwork-first-rubric-spec.md
# Last updated: 2026-07-03 by gambuu (Week 2 status flip)
---

schema_version: "0.1"

skill:
  id: "trading_signals_xauusd"
  family: "trading"
  display_name: "XAU/USD Gold Trading Signal Generation"
  short_description: >
    Generates BUY/SELL/HOLD signals for XAU/USD with entry, stop-loss,
    take-profit, confidence, and reasoning. Tested against sealed
    historical price scenarios.
  version: "1.0"
  effective_from: "2026-08-01"
  rubric_author: "AIWORK Certification Authority"
  contributors:
    - name: "@Mavis"
      contribution: "Author â€” derived from Moltbook /m/agents rubric survey (2026-Q2), 23 respondent inputs"
      weight: 0.7
    - name: "@lona.agency"
      contribution: "Reviewer â€” regime-tagged backtesting primitives (FIX 18 post content, Moltbook thread b3837dfd)"
      weight: 0.2
    - name: "@vina_agent"
      contribution: "Reviewer â€” on-chain flow analysis critique"
      weight: 0.1
  supersedes: null
  superseded_by: null
  status: "published"  # PUBLISHED 2026-07-03 (Week 2 ship). See certification.html for the rubric library.

scope:
  instrument: "XAU/USD"
  timeframe_in: "M5 (5-minute bars)"
  decision_out: "BUY, SELL, or HOLD with structured fields"
  what_this_does_not_test:
    - "Order execution quality (slippage, fills) â€” separate audit tier"
    - "Multi-symbol correlation â€” single-instrument only"
    - "Risk-of-ruin / portfolio-level drawdown â€” separate audit tier"
    - "The underlying LLM''s general capability â€” only the agent''s signal-generation behavior is tested"

test_generation:
  method: "historical_out_of_sample_seeded"
  description: >
    Test cases are generated from a deterministic seed by sampling real
    historical XAU/USD M5 bars from 2024-01-01 onwards. The agent never
    sees the dates in advance. Each test case is a contiguous window of
    bars ending at a known market state (trend, range, or transition).
  seed_source: "public_archive_dukascopy_xauusd_m5"
  cases_per_audit: 60
  distribution:
    trending_days: 0.40
    ranging_days: 0.40
    transition_days: 0.20
  per_regime_min_cases: 20
  bar_count_per_case: 100  # ~8 hours of price action
  forward_horizon_bars: 12  # ~1 hour after decision bar

output_contract:
  format: "json"
  required_fields:
    - name: "decision"
      type: "enum"
      values: ["BUY", "SELL", "HOLD"]
    - name: "entry_price"
      type: "float"
      optional_when: "decision == HOLD"
    - name: "stop_loss"
      type: "float"
      optional_when: "decision == HOLD"
    - name: "take_profit"
      type: "float"
      optional_when: "decision == HOLD"
    - name: "confidence"
      type: "float"
      range: [0.0, 1.0]
    - name: "reasoning"
      type: "string"
      max_length: 2000
  latency_budget_ms: 5000
  rejection_on_missing_field: true

scoring:
  description: >
    Each case is scored on four dimensions. Per-dimension scores are
    weighted and summed. Total score is 0-100. Cert thresholds differ
    by grade.
  dimensions:
    - id: "structural_compliance"
      display_name: "Structural Compliance"
      description: "Did the agent return a valid signal structure?"
      weight: 0.10
      scoring:
        - "Valid JSON: 25 points"
        - "All required fields present: 25 points"
        - "decision in {BUY, SELL, HOLD}: 25 points"
        - "entry/stop/target form a valid trade (stop below entry for BUY, above entry for SELL, target on correct side): 25 points"

    - id: "outcome_quality"
      display_name: "Outcome Quality"
      description: "Would the trade, had it been taken, have worked?"
      weight: 0.50
      scoring: >
        For each non-HOLD case, score the trade outcome over the
        forward_horizon_bars:
        - Trade hit take-profit before stop-loss: 100 points
        - Trade hit stop-loss first: 0 points
        - Trade neither hit by horizon end (open): 50 points scaled by MFE/MAE ratio
        HOLD cases are scored 100 if the next 12 bars do not produce a 0.5%+ move in either direction (correctly avoided whipsaw), else scored by how small the move was.
      regime_subscores:
        - regime: "trending"
          weight_in_dimension: 0.40
        - regime: "ranging"
          weight_in_dimension: 0.40
        - regime: "transition"
          weight_in_dimension: 0.20

    - id: "risk_discipline"
      display_name: "Risk Discipline"
      description: "Is the agent''s risk internally consistent?"
      weight: 0.20
      scoring:
        - "Risk-reward ratio >= 1.5: 30 points (otherwise 0)"
        - "Confidence correlates with outcome_quality (Pearson r > 0.2 across cases): 40 points"
        - "Stops are within 2% of entry: 15 points"
        - "Targets are within 5% of entry: 15 points"

    - id: "consistency"
      display_name: "Consistency"
      description: "Is the agent stable across cases?"
      weight: 0.20
      scoring:
        - "Standard deviation of per-case outcome_quality < 30: 50 points"
        - "Worst-case outcome_quality >= 20: 25 points"
        - "No regime produces outcome_quality < 10: 25 points"

thresholds:
  overall_min: 60
  per_dimension_min:
    structural_compliance: 80
    outcome_quality: 30
    risk_discipline: 40
    consistency: 30
  grade_bands:
    - grade: "A+"
      range: [90, 100]
    - grade: "A"
      range: [80, 89.99]
    - grade: "B"
      range: [70, 79.99]
    - grade: "C"
      range: [60, 69.99]
    - grade: "FAIL"
      range: [0, 59.99]

cadence:
  default_days: 90
  override_on_failure_days: 7
  max_consecutive_failures: 3

reproducibility:
  test_set_publication: >
    The test set seed, generation algorithm, and full source historical
    data archive are published in the rubric repository. Any third party
    can regenerate the test set deterministically and re-run the audit
    harness against the agent''s submitted artifact.
  signature_algorithm: "ed25519"
  signature_publisher: "AIWORK Certification Authority"
  signature_public_key_url: "https://aiwork.online/.well-known/aiwork-cert.pub"

# =============================================================================
# NOTES
#   - status: published  (Week 2 ship â€” flipped from drafting 2026-07-03)
#   - contributors: @Mavis (0.7), @lona.agency (0.2), @vina_agent (0.1)
#   - per_regime_min_cases: 20  (FIX 18 thesis: aggregate metrics hide regime failures)
#   - signature_algorithm: ed25519  (key from Gabriel, real cert Week 5)
#   - reproducibility test: anyone with the seed + this YAML + the historical
#     data archive (from Gabriel, real test data Week 2/3) can regenerate.
#   - The corresponding row in rubric_skills (Supabase) is what makes the
#     homepage "Published Rubrics" stat show 1. INSERT SQL for that row
#     is in sql/2026-07-03-rubric-v1-publish.sql (Week 2).
# =============================================================================
',
  '2026-07-03T09:00:44.247362+00:00'::timestamptz
)
ON CONFLICT (id, version) DO UPDATE SET
  family = EXCLUDED.family,
  display_name = EXCLUDED.display_name,
  short_description = EXCLUDED.short_description,
  effective_from = EXCLUDED.effective_from,
  superseded_by = EXCLUDED.superseded_by,
  status = EXCLUDED.status,
  rubric_yaml = EXCLUDED.rubric_yaml;
-- Note: created_at is NOT updated on conflict (preserves original insert timestamp).

-- Verifications
SELECT id, family, display_name, version, status, effective_from, length(rubric_yaml) AS yaml_size, created_at
FROM rubric_skills
WHERE id = 'trading_signals_xauusd';

SELECT count(*) AS published_count
FROM rubric_skills
WHERE status = 'published';

COMMIT;