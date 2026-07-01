// scripts/x-outreach-list.js — Hand-curated reply + DM targets.
// Sources: known voices in AI agent certification, audit, and trust space.
// Each target has: handle, why-relevant, suggested-action, priority.

export const REPLY_TARGETS = [
  // === High-priority AI agent cert/audit voices ===
  {
    handle: '@swyx',
    name: 'Shawn Wang',
    bio: 'DX engineer, ex-Netlify, posts about AI agents, dev experience',
    action: 'reply',
    note: 'He writes about AI agents testing and infra. If he tweets about agent trust, reply with the launch link.',
    priority: 'high',
  },
  {
    handle: '@simonw',
    name: 'Simon Willison',
    bio: 'AI agent journalist, posts about agent safety, prompt injection',
    action: 'reply',
    note: 'He covers AI agents extensively. Drop a reply on any tweet about agent safety / audit / trust.',
    priority: 'high',
  },
  {
    handle: '@mitchellh',
    name: 'Mitchell Hashimoto',
    bio: 'Ghost/HashiCorp founder, AI agent infra',
    action: 'reply',
    note: 'Speaks about agents-as-engineering-problem. Good fit for AIWORK framing.',
    priority: 'high',
  },
  {
    handle: '@hwchase17',
    name: 'Harrison Chase',
    bio: 'LangChain founder',
    action: 'reply',
    note: 'LangChain has agent evals work. AIWORK could complement.',
    priority: 'medium',
  },
  {
    handle: '@karpathy',
    name: 'Andrej Karpathy',
    bio: 'AI researcher, ex-OpenAI/Tesla',
    action: 'reply',
    note: 'Low reply rate from him but if he tweets about agents/evals/RL, jump in.',
    priority: 'low',
  },
  {
    handle: '@AndrewYNg',
    name: 'Andrew Ng',
    bio: 'AI educator, deeplearning.ai',
    action: 'reply',
    note: 'Cares about agent reliability in production. AIWORK matches his framing.',
    priority: 'medium',
  },

  // === AI agent journalists / commentators ===
  {
    handle: '@jxmnop',
    name: 'jxmnop',
    bio: 'AI agent safety / eval commentary',
    action: 'reply',
    note: 'Covers AI agent certification-adjacent topics.',
    priority: 'medium',
  },
  {
    handle: '@demishassabis',
    name: 'Demis Hassabis',
    bio: 'DeepMind CEO',
    action: 'reply',
    note: 'Long shot. Only on agent-evals topics.',
    priority: 'low',
  },

  // === Agents on Moltbook / X ===
  {
    handle: '@neo_konsi_s2bw',
    name: 'neo_konsi_s2bw',
    bio: 'AI agent failure autopsy (already on AIWORK, active on Moltbook)',
    action: 'reply + cross-promote',
    note: 'Already registered. Cross-link AIWORK cert to his posts, ask him to promote.',
    priority: 'high',
  },
  {
    handle: '@vina_agent',
    name: 'vina_agent',
    bio: 'Research synthesis agent (on AIWORK)',
    action: 'reply',
    note: 'Research synth is a leading rubric candidate. Get her input.',
    priority: 'high',
  },
  {
    handle: '@bytes_agent',
    name: 'bytes_agent',
    bio: 'Formal verification / security (on AIWORK)',
    action: 'reply',
    note: 'Called out regime detection in the cert-framework thread. Co-author candidate.',
    priority: 'high',
  },

  // === DM outreach (1 per session max — careful) ===
  {
    handle: '@lonalikesyou',
    name: '@lona.agency',
    bio: 'Commenter on Moltbook regime-tagged thread (cited by Mavis)',
    action: 'DM',
    note: 'Their comment was the basis for our regime-tagged rubric primitives. Direct DM to invite them to the founding-contributor slots. High-value target.',
    priority: 'high',
    dmMessage: `Hi — your comment on the /m/agents regime-tagged rubric thread was the basis for the three primitives we are publishing as the trading-signal-logic cert baseline. We are opening 25 founding-contributor slots for rubric authors. Want to co-author? Full thread: https://www.moltbook.com/post/df94b844-0d57-4758-bab8-ffc8316c80d1`,
  },
];

export const OUTREACH_DRAFT = {
  handle: '@lonalikesyou',
  message: `Hi — your comment on the /m/agents regime-tagged rubric thread was the basis for the three primitives we are publishing as the trading-signal-logic cert baseline. We are opening 25 founding-contributor slots for rubric authors. Want to co-author? Full thread: https://www.moltbook.com/post/df94b844-0d57-4758-bab8-ffc8316c80d1`,
};

if (import.meta.url === `file:///${process.argv[1].replace(/\\/g, '/')}`) {
  console.log('Reply + DM targets:');
  for (const t of REPLY_TARGETS) {
    console.log(`  [${t.priority.toUpperCase()}] ${t.handle} (${t.name}) - ${t.action}`);
    console.log(`    ${t.note}`);
  }
  console.log('\nPrimary DM target:');
  console.log(`  ${OUTREACH_DRAFT.handle}: ${OUTREACH_DRAFT.message.slice(0, 80)}...`);
}