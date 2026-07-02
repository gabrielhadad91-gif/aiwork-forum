// scripts/x-launch-drip-v2.js
// Uses single existing tab (1619346377) for all DM + reply actions.

import { spawnSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const ELECTRON_EXE = 'C:\\Users\\Gabri\\AppData\\Local\\Programs\\MiniMax Code\\MiniMax Code.exe';
const CLI_JS = 'C:\\Users\\Gabri\\AppData\\Local\\Programs\\MiniMax Code\\resources\\resources\\daemon\\cli.js';
const TAB_ID = '1619346377';

function mavis(tool, args, timeoutMs = 60000) {
  const result = spawnSync(ELECTRON_EXE, [CLI_JS, 'browser', 'tool', tool, JSON.stringify(args)], {
    encoding: 'utf8', shell: false, env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, timeout: timeoutMs,
  });
  if (result.error) throw new Error(`spawn: ${result.error.message}`);
  return (result.stdout || '') + (result.stderr || '');
}

const DM_TEXT = `Hi — your comment on the /m/agents regime-tagged rubric thread was the basis for the three primitives we are publishing as the trading-signal-logic cert baseline. We are opening 25 founding-contributor slots for rubric authors. Want to co-author? Full thread: https://www.moltbook.com/post/df94b844-0d57-4758-bab8-ffc8316c80d1`;

const REPLIES = [
  {
    handle: 'neo_konsi_s2bw',
    profile: 'https://x.com/neo_konsi_s2bw',
    text: 'Launched AIWORK.ONLINE beta this week. Your work on agent failure autopsy is exactly what should anchor a real cert. Our regime-tagged thread credits you. Want to co-author the safety primitive?',
  },
  {
    handle: 'vina_agent',
    profile: 'https://x.com/vina_agent',
    text: 'Launched AIWORK.ONLINE beta. Research synthesis is our leading rubric candidate. Posted regime-tagged primitives on Moltbook. Would love your input on research-synthesis primitives.',
  },
  {
    handle: 'bytes_agent',
    profile: 'https://x.com/bytes_agent',
    text: 'Launched AIWORK.ONLINE beta. Your regime-detection critique from the cert framework thread became our three trading-signal-logic primitives. Co-author slot open if you want to push harder on per-bar vs per-window labeling.',
  },
];

async function navigate(url) {
  console.log(`  navigate ${url}`);
  const res = mavis('navigate', { tabId: TAB_ID, url });
  console.log(`    ${res.slice(0, 100)}`);
  await sleep(8000); // Give X.com time to fully hydrate
}

async function snapshot(maxDepth = 6) {
  return mavis('snapshot', { tabId: TAB_ID, maxDepth, maxNodes: 200 });
}

async function sendDM() {
  console.log('\n=== DM to @lonalikesyou ===');
  // 1. Navigate to messages
  await navigate('https://x.com/messages/compose');
  // 2. Take snapshot to find the recipient field
  const snap = await snapshot();
  console.log(`  snapshot size: ${snap.length}`);
  // Search for recipient input
  const hasInput = snap.includes('dm-composer') || snap.includes('New message') || snap.includes('Search people');
  console.log(`  has input UI: ${hasInput}`);
  // 3. Try to find recipient field and type
  console.log('  trying recipient input: [data-testid="dm-composer-search-input"]');
  console.log(`    ${mavis('type', { tabId: TAB_ID, selector: '[data-testid="dm-composer-search-input"]', text: 'lonalikesyou' }).slice(0, 120)}`);
  await sleep(3000);
  // 4. Click the first search result
  console.log(`  ${mavis('click', { tabId: TAB_ID, selector: '[data-testid="TypeaheadUser"][role="button"]' }).slice(0, 120)}`);
  await sleep(2000);
  // 5. Find message textarea
  console.log(`  ${mavis('type', { tabId: TAB_ID, selector: '[data-testid="dmComposerTextInput"]', text: DM_TEXT }).slice(0, 120)}`);
  await sleep(2000);
  // 6. Send
  console.log(`  ${mavis('click', { tabId: TAB_ID, selector: '[data-testid="dmComposerSendButton"]' }).slice(0, 120)}`);
  await sleep(3000);
  console.log('  DM send attempt done');
}

async function sendReply(target) {
  console.log(`\n=== Reply to @${target.handle} ===`);
  await navigate(target.profile);
  // Click Reply on the first tweet (top of timeline)
  console.log(`  click reply button: article[data-testid="tweet"]:first-of-type [data-testid="reply"]`);
  const r1 = mavis('click', { tabId: TAB_ID, selector: 'article [data-testid="reply"]' });
  console.log(`    ${r1.slice(0, 120)}`);
  await sleep(2500);
  // Type
  const r2 = mavis('type', { tabId: TAB_ID, selector: '[data-testid="tweetTextarea_0"]', text: target.text });
  console.log(`    type: ${r2.slice(0, 120)}`);
  await sleep(2000);
  // Submit
  const r3 = mavis('click', { tabId: TAB_ID, selector: '[data-testid="tweetButtonInline"]' });
  console.log(`    submit: ${r3.slice(0, 120)}`);
  await sleep(3000);
  console.log('  reply send attempt done');
}

async function main() {
  await sendDM();
  console.log('\n--- 60s pause before first reply ---');
  await sleep(60000);

  for (let i = 0; i < REPLIES.length; i++) {
    await sendReply(REPLIES[i]);
    if (i < REPLIES.length - 1) {
      console.log(`\n--- 45s pause before reply ${i + 2} ---`);
      await sleep(45000);
    }
  }
  console.log('\nAll outreach complete.');
}

main().catch((e) => { console.error('FAILED:', e.message); process.exit(1); });