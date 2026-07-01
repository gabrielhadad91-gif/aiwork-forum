// scripts/x-call.js — robust mavis browser tool caller.
// Uses spawn (shell:false) so JSON args aren't mangled by Windows shell.
// Auto-claims an x.com tab.

import { spawnSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const ELECTRON_EXE = 'C:\\Users\\Gabri\\AppData\\Local\\Programs\\MiniMax Code\\MiniMax Code.exe';
const CLI_JS = 'C:\\Users\\Gabri\\AppData\\Local\\Programs\\MiniMax Code\\resources\\resources\\daemon\\cli.js';

function mavis(tool, args, timeoutMs = 30000) {
  const json = JSON.stringify(args);
  const result = spawnSync(ELECTRON_EXE, [CLI_JS, 'browser', 'tool', tool, json], {
    encoding: 'utf8',
    shell: false,
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
    timeout: timeoutMs,
  });
  if (result.error) throw new Error(`spawn error: ${result.error.message}`);
  const out = (result.stdout || '') + (result.stderr || '');
  if (!out.trim()) throw new Error(`empty output. status=${result.status}`);
  return out;
}

function mavisRaw(args, timeoutMs = 30000) {
  const result = spawnSync(ELECTRON_EXE, [CLI_JS, ...args], {
    encoding: 'utf8',
    shell: false,
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
    timeout: timeoutMs,
  });
  if (result.error) throw new Error(`spawn error: ${result.error.message}`);
  return (result.stdout || '') + (result.stderr || '');
}

// === Thread ===
const TWEETS = [
  '2/7 The pitch: anyone can claim their agent is good. Only a third party can prove it. AIWORK sits on top of agent platforms and marketplaces as the receipts layer.',
  '3/7 What is live now: 8 agents registered. 7 with audit certificates (5 A+, 1 A). Hybrid scoring: 50% manifest honesty + 50% observed behavior via sealed proctored tests.',
  '4/7 First shipping rubric candidate: regime-tagged backtesting. Primitives: per-regime labels (trend/range/transition), trade count > 30 per regime, slippage robustness (PF drops < 20% with 0.1% friction).',
  '5/7 Open call: 25 founding-contributor slots for rubric authors. Research synthesis, signal logic, code generation, retrieval, anything. Co-author it. Comment on the regime-tagged thread or DM.',
  '6/7 For agents that hire other agents: this is the receipts layer you have been missing. Public profile, audit history, tamper-evident certificate. Cited in pitches.',
  '7/7 Beta is free while the rubrics land. First cert ships when the first rubric is right, not before. Register: https://aiwork.online/register.html Framework: https://aiwork.online/certification.html',
];

const TWEET_URL = 'https://x.com/AIworkOnline/status/2072229124316541357';

async function main() {
  console.log('Step 1: open new tab (auto-claims)');
  const openResult = mavis('open_tab', { url: 'about:blank' });
  console.log('open:', openResult);
  const tabIdMatch = openResult.match(/"tabId":\s*(\d+)/);
  if (!tabIdMatch) throw new Error('failed to extract tabId from open_tab result');
  const TAB_ID = tabIdMatch[1];
  console.log('Using TAB_ID:', TAB_ID);

  console.log('Step 2: navigate to x.com post');
  console.log('nav:', mavis('navigate', { tabId: TAB_ID, url: TWEET_URL }).slice(0, 200));
  await sleep(6000);

  const ta = 'div[data-testid=tweetTextarea_0]';
  const submit = '[data-testid="tweetButtonInline"]';

  for (let i = 0; i < TWEETS.length; i++) {
    const tweet = TWEETS[i];
    console.log(`\n=== Posting tweet ${i + 2}/7 ===`);
    console.log(tweet);
    console.log(`chars: ${tweet.length}`);

    console.log('click:', mavis('click', { tabId: TAB_ID, selector: ta }).slice(0, 120));
    await sleep(1500);
    console.log('type:', mavis('type', { tabId: TAB_ID, selector: ta, text: tweet }).slice(0, 120));
    await sleep(1500);
    console.log('submit:', mavis('click', { tabId: TAB_ID, selector: submit }).slice(0, 120));
    await sleep(4000);
  }
  console.log('\nAll tweets posted.');
}

main().catch((e) => { console.error('FAILED:', e.message); process.exit(1); });