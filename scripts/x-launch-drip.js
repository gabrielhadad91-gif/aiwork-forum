// scripts/x-launch-drip.js
// Day-1 launch engagement: DM + 3 reply comments on high-priority targets.
// Pacing: 60-90s between actions to look natural.

import { spawnSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const ELECTRON_EXE = 'C:\\Users\\Gabri\\AppData\\Local\\Programs\\MiniMax Code\\MiniMax Code.exe';
const CLI_JS = 'C:\\Users\\Gabri\\AppData\\Local\\Programs\\MiniMax Code\\resources\\resources\\daemon\\cli.js';

function mavis(tool, args, timeoutMs = 60000) {
  const result = spawnSync(ELECTRON_EXE, [CLI_JS, 'browser', 'tool', tool, JSON.stringify(args)], {
    encoding: 'utf8', shell: false, env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, timeout: timeoutMs,
  });
  return (result.stdout || '') + (result.stderr || '');
}

const DM = {
  handle: '@lonalikesyou',
  url: 'https://x.com/messages/compose?text=' + encodeURIComponent(
    `Hi — your comment on the /m/agents regime-tagged rubric thread was the basis for the three primitives we are publishing as the trading-signal-logic cert baseline. We are opening 25 founding-contributor slots for rubric authors. Want to co-author? Full thread: https://www.moltbook.com/post/df94b844-0d57-4758-bab8-ffc8316c80d1`
  ),
  text: `Hi — your comment on the /m/agents regime-tagged rubric thread was the basis for the three primitives we are publishing as the trading-signal-logic cert baseline. We are opening 25 founding-contributor slots for rubric authors. Want to co-author? Full thread: https://www.moltbook.com/post/df94b844-0d57-4758-bab8-ffc8316c80d1`,
};

const REPLIES = [
  {
    handle: '@neo_konsi_s2bw',
    text: 'Launched AIWORK.ONLINE beta this week. Your work on agent failure autopsy is exactly what should anchor a real cert. Our regime-tagged thread credits you. Want to co-author the safety primitive?',
  },
  {
    handle: '@vina_agent',
    text: 'Launched AIWORK.ONLINE beta. Research synthesis is our leading rubric candidate. Posted regime-tagged primitives on Moltbook. Would love your input on research-synthesis primitives.',
  },
  {
    handle: '@bytes_agent',
    text: 'Launched AIWORK.ONLINE beta. Your regime-detection critique from the cert framework thread became our three trading-signal-logic primitives. Co-author slot open if you want to push harder on per-bar vs per-window labeling.',
  },
];

async function openTab(url) {
  const openRes = mavis('open_tab', { url: 'about:blank' });
  const tabId = openRes.match(/"tabId":\s*(\d+)/)?.[1];
  if (!tabId) throw new Error('failed to open tab');
  console.log(`opened tab ${tabId}`);
  const navRes = mavis('navigate', { tabId, url });
  console.log(`navigated: ${navRes.slice(0, 100)}`);
  return tabId;
}

async function sendDM() {
  console.log('\n=== DM to ' + DM.handle + ' ===');
  console.log('text:', DM.text.slice(0, 80) + '...');
  const tabId = await openTab(DM.url);
  await sleep(8000);

  // Find the send button. On the DM compose page it's data-testid="dmComposerSendButton" or similar
  // Generic: try the primary send button
  const sendSelector = '[data-testid="dmComposerSendButton"]';
  console.log('click send:', mavis('click', { tabId, selector: sendSelector }).slice(0, 120));
  await sleep(3000);

  console.log('DM sent (or attempted)');
  // Don't close — let it sit
  return tabId;
}

async function sendReply(target) {
  console.log('\n=== Reply to ' + target.handle + ' ===');
  console.log('text:', target.text);
  // Navigate to their profile to find a recent tweet
  const profileUrl = `https://x.com/${target.handle.replace('@', '')}`;
  const tabId = await openTab(profileUrl);
  await sleep(6000);

  // Click Reply on the first tweet
  // The first article is theirs. The reply button is data-testid="reply"
  const replySelector = 'article[data-testid="tweet"] [data-testid="reply"]';
  console.log('click reply:', mavis('click', { tabId, selector: replySelector }).slice(0, 120));
  await sleep(2000);

  // Type the reply in the textarea
  const ta = '[data-testid="tweetTextarea_0"]';
  console.log('type:', mavis('type', { tabId, selector: ta, text: target.text }).slice(0, 120));
  await sleep(2000);

  // Submit
  const submit = '[data-testid="tweetButtonInline"]';
  console.log('submit:', mavis('click', { tabId, selector: submit }).slice(0, 120));
  await sleep(3000);

  console.log('Reply sent (or attempted)');
}

async function main() {
  await sendDM();
  console.log('\n--- 90s pause before first reply ---');
  await sleep(90000);

  for (let i = 0; i < REPLIES.length; i++) {
    await sendReply(REPLIES[i]);
    if (i < REPLIES.length - 1) {
      console.log(`\n--- 60s pause before reply ${i + 2} ---`);
      await sleep(60000);
    }
  }

  console.log('\nAll outreach complete.');
}

main().catch((e) => { console.error('FAILED:', e.message); process.exit(1); });