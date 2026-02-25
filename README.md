# How to Build an Autonomous AI Agent on a Mac mini

A complete, tested guide to building an always-on AI agent with its own identity, crypto wallet, and three-tier inference fallback chain -- powered by a Mac mini and the Morpheus decentralized AI network.

Every step in this guide was tested on real hardware with real money. 12 gotchas were hit during the build and fixes for all of them are documented.

---

## What You'll End Up With

- A Mac mini running headless 24/7 with a dedicated user account for the agent
- An AI agent with its own email, GitHub, crypto wallet, and phone number
- Three-tier inference fallback: cloud AI (Claude) + decentralized (Morpheus) + local (Ollama)
- A defined persona that makes the agent consistent and predictable
- On-chain financial guardrails via a Safe multi-sig wallet
- A kill switch that halts everything immediately

## Three Ways to Use This Guide

| Resource | What It Is | Best For |
|----------|-----------|----------|
| [Overview](SETUP-OVERVIEW.pdf) | 4-page summary | Understanding the architecture quickly |
| [Full Guide](AUTONOMOUS-AGENT-SETUP-GUIDE.pdf) | 17-page walkthrough | Reading through the complete build |
| [Claude Code Prompt](AUTONOMOUS-AGENT-SETUP-PROMPT.md) | Interactive agent prompt | Paste into [Claude Code](https://claude.ai/code) and get walked through the build step by step |

The **Claude Code Prompt** is the fastest path. Paste it into a Claude Code session and the AI will guide you through each phase interactively -- asking what you have, adapting to your setup, and flagging gotchas before you hit them.

## Why This Architecture

### Three independent inference paths

```
1. Claude Opus (cloud)      -- best quality, paid subscription
2. Morpheus (decentralized)  -- no per-request cost, tokens returned after use
3. Ollama (local)            -- free, private, always available
```

If Claude is down or rate-limited, the agent falls back to Morpheus. If Morpheus providers are sparse, it falls back to local Ollama. The agent always has a way to think.

### Why Morpheus?

Morpheus is a peer-to-peer AI inference network. Instead of paying per-request to a cloud API, you stake MOR tokens to open a 7-day session. When the session expires, **your tokens come back**. You're renting access, not spending money.

No API keys. No rate limits. No single company controlling access. Your agent gets inference that doesn't depend on anyone's billing system staying online.

### Why a Safe multi-sig?

Software guardrails are breakable -- a prompt injection or bug could bypass them. The agent's funds live in a Safe multi-sig wallet with on-chain spending limits enforced by the blockchain itself. The agent proposes transactions; spending above the threshold requires your co-signature. The contract is the security boundary, not code the agent could override.

## The Build in Seven Phases

| Phase | What | Time |
|-------|------|------|
| 0. Discovery | Define what you're building, choose a name | 30 min |
| 1. Mac mini Setup | Headless, remote access, always-on | 2-3 hours |
| 2. Agent Identity | Email, secrets, wallet, GitHub | 2-3 hours |
| 3. Communication | Signal via VoIP (JMP.chat) | 1-2 hours |
| 4. Model Routing | Cloud + Morpheus + Local fallback chain | 3-4 hours |
| 5. Persona Files | SOUL.md, AGENTS.md, MEMORY.md, etc. | 1-2 hours |
| 6. Security | Hardening checklist | 1 hour |
| 7. Operations | Trust-building, ongoing monitoring | Ongoing |

**Total: about a weekend** for the basic agent. Add another day for the full Morpheus integration.

## Cost

| Item | Cost | Type |
|------|------|------|
| Mac mini M4 (16GB) | ~$600 | One-time |
| HDMI dummy plug | ~$10 | One-time |
| Proton Mail Plus | ~$4/month | Recurring |
| VoIP number (JMP.chat) | ~$4/month | Recurring |
| Cloud AI subscription | ~$20-200/month | Recurring |
| ETH for gas (Base) | ~$10-50 | Refillable |
| MOR for staking | ~$10 | Reusable (tokens return) |
| Ollama (local) | Free | Needs a Mac with RAM |

**Total recurring: ~$28-208/month** depending on your cloud AI tier. The Morpheus layer reduces dependence on paid cloud inference over time.

## Common Gotchas

These are real bugs from the original build, with fixes:

1. **signal-cli platform mismatch** -- frameworks download the wrong binary on ARM Macs. Install via Homebrew.
2. **Signal captcha on headless machines** -- solve on your laptop at signalcaptchas.org, copy the token.
3. **macOS Keychain locks in SSH** -- run `security unlock-keychain` before accessing secrets.
4. **LaunchAgents may not load on headless Macs** -- depends on GUI session. Test after reboot; use cron as fallback.
5. **Morpheus proxy-router overflow (v5.11.0)** -- reset allowance to 0, let the router manage.
6. **Morpheus model IDs wrong out of the box** -- verify against the actual network.
7. **Apple Silicon is fast for local inference** -- M3 Ultra 96GB runs Llama 3.3 70B. Don't underestimate it.
8. **Heredocs corrupt over SSH** -- use single-line commands or scp files directly.
9. **Public RPC stale nonce** -- sequential Safe transactions fail on public RPCs. Use a private RPC.
10. **Treasury scripts require SAFE_RPC** -- not optional despite what docs said. No public fallback by design.
11. **Treasury keychain defaults won't match your setup** -- override with env vars.

## Validate Your Setup

After completing the build (or anytime you want a health check), run the validation script to verify your setup matches the guide:

```bash
# One-time setup: copy the config template and fill in your values
cp validate-config.example.sh validate-config.sh
nano validate-config.sh

# Run all checks
./validate.sh

# Run as admin for SSH/firewall checks, as agent for workspace/keychain checks
# Checks that need the other user context are automatically skipped

# Other options
./validate.sh --phase 1      # Run only Phase 1 (Mac mini setup) checks
./validate.sh --json          # Machine-readable JSON output
./validate.sh --quiet         # Summary only
```

The script checks ~72 items across all 7 phases: user accounts, SSH hardening, Proton Bridge, Morpheus services, Ollama, persona files, secret management, and security hardening. Each run writes both a human-readable log and a JSON log to `~/.agent-validate/` -- the JSON log contains everything needed to diagnose issues remotely.

Checks are scored:
- **95-100 (Excellent):** Setup matches the guide
- **85-94 (Good):** Minor recommendations not followed
- **70-84 (Needs attention):** Some requirements not met
- **Below 70 (Critical):** Significant gaps in setup

Optional components (Signal, Ollama, Safe multi-sig) are skipped entirely when disabled in config, so they don't penalize your score.

## Core Principles

1. **Identity separation.** The agent is not you. Own email, wallet, accounts. Your credentials never touch its machine.
2. **On-chain guardrails.** Financial limits enforced by a Safe multi-sig contract, not by software.
3. **Agent proposes, human approves.** Every financial move explained in plain language first.
4. **Operational transparency.** Silence looks like death. The agent communicates what it's doing.
5. **Kill switch.** "STOP ALL IMMEDIATELY" halts everything. No arguments.

## Contributing

Built your own agent? Found a bug not in the guide? Open a PR.

- Add gotchas you discovered
- Share alternative framework configs
- Improve the Morpheus setup instructions as the network evolves
- Add instructions for Linux (the guide is macOS-focused)

## License

MIT
