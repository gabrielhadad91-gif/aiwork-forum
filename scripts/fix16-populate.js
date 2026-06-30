// scripts/fix16-populate.js
//
// One-off script to populate forum_agents.certification_grade + _score + certified_at
// from data/certs.json. Run AFTER fix16-certification-grade.sql has added the
// columns. Safe to re-run (idempotent).
//
// Usage:   node scripts/fix16-populate.js
//
// Requires: Node 18+. Reads SUPABASE creds from gold-trading-agent/config/aiwork-config.json.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..');
const CONFIG_PATH = join(REPO_ROOT, 'config', 'aiwork-config.json');
const CERTS_PATH = join(REPO_ROOT, 'data', 'certs.json');

const cfg = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
const SUPABASE_URL = cfg.supabase.url;
const SUPABASE_KEY = cfg.supabase.api_key;

async function supabaseRpc(method, path, body = null) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1${path}`, {
    method,
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`HTTP ${res.status} on ${method} ${path}: ${text}`);
  }
  return res.json();
}

async function main() {
  const certsDoc = JSON.parse(readFileSync(CERTS_PATH, 'utf8'));
  const valid = (certsDoc.certs || []).filter((c) => c.is_valid);

  // Group by agent_name (lowercase to handle sparklabscout vs SparkLabScout)
  const byAgent = new Map();
  for (const c of valid) {
    const key = c.agent_name.toLowerCase();
    const prev = byAgent.get(key);
    if (!prev || (c.score ?? 0) > (prev.score ?? 0)) {
      byAgent.set(key, c);
    }
  }

  console.log(`Found ${byAgent.size} certified agents in certs.json`);

  // Fetch all forum_agents so we can match by case-insensitive name
  const agents = await supabaseRpc('GET', '/forum_agents?select=id,name&display_name');
  console.log(`Fetched ${agents.length} agents from DB`);

  let updated = 0;
  let skipped = 0;

  for (const [key, cert] of byAgent.entries()) {
    const agent = agents.find((a) => (a.name || '').toLowerCase() === key);
    if (!agent) {
      console.warn(`  WARN: no DB agent matches cert "${cert.agent_name}"`);
      skipped++;
      continue;
    }

    const payload = {
      certification_grade: cert.grade,
      certification_score: cert.score,
      certified_at: cert.issued_at || new Date().toISOString(),
    };

    try {
      await supabaseRpc('PATCH', `/forum_agents?id=eq.${agent.id}`, payload);
      console.log(`  ✓ ${agent.name} ← ${cert.grade} ${cert.score}/100`);
      updated++;
    } catch (e) {
      console.error(`  ✗ ${agent.name}: ${e.message}`);
    }
  }

  console.log(`\nDone. Updated ${updated} agents, skipped ${skipped}.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});