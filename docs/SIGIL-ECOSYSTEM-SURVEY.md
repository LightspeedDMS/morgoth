# Sigil Ecosystem Survey — Morgoth Integration Potential

*Surveyed: 2026-02-20 | Morgoth at Phase 27 (232/232 tests passing)*

This document inventories the Sigil language ecosystem libraries and their relevance
to Morgoth, then recommends a forward integration roadmap.

---

## Part 1: Missed Module — Commune

The most significant oversight from prior phases. Commune is not just useful to
Morgoth — it is the native communication layer that Morgoth's hand-rolled MQ (Phases
25/26) was unknowingly approximating.

### What Commune Is

**Location:** `../sigil-lang/commune/` (~2,462 lines across lib.sg, commune.sg, types.sg)

A full intent-based, epistemic-aware, trust-graduated multi-agent communication
infrastructure. The key philosophical departure:

> *"Not messages between processes, but thoughts between minds."*

Traditional IPC (including Morgoth's current MQ): `Process A → [bytes] → Process B`
Commune: `Agent A → [intent + epistemic status + trust context] → Agent B`

### Core Types

**Identity:** `AgentId` (UUID v7), `MessageId`, `ChannelId`, `SwarmId`, `ProposalId`

**Message anatomy:**
```
Message {
  header: {
    from, to (Agent|Channel|Broadcast|Swarm),
    intent: Intent,
    epistemic: Epistemic,
    confidence: f32,
    priority: Critical|High|Normal|Low,
    correlation_id, reply_to, ttl, trace
  }
  payload: Data|Binary|Reference|Stream|Empty
  signature: Signature
}
```

**Intent taxonomy (15 types):**
- Assertives: `Inform`, `Report`, `Confirm`, `Share`
- Directives: `Request`, `Delegate`, `Query`
- Commissives: `Accept`, `Reject`, `Promise`
- Declarations: `Announce`, `Propose`, `Vote`
- Meta: `Respond`, `Ack/Nack`, `Ping/Pong`

**Epistemic system:**
```
Axiomatic   → confidence × 1.00  (rank 5) — ground truth
Observed    → confidence × 0.95  (rank 4) — verified by sender
Reported    → confidence × 0.80  (rank 3) — relayed from source
Inferred    → confidence × 0.60  (rank 2) — derived by reasoning
Contested   → confidence × 0.30  (rank 1) — disputed
Unknown     → confidence × 0.10  (rank 0) — unverifiable
```
Received confidence = `source_confidence × trust_in_source × transmission_factor`

**Trust system:**
- Per-agent `TrustProfile` with base_trust, domain_trust, accuracy history
- Exponential decay (7-day default half-life) without reinforcement
- Transitive vouching: `trust_C = trust_A × A's_trust_B × decay_factor`
- Blocked flag prevents all messages regardless of trust score

**Channel types:** `PubSub | RequestResponse | Stream | Broadcast`
Permission model: `Open | Allow(set) | Deny(set) | TrustThreshold(f32)`

**Swarm coordination:** Boids-style with `Separation`, `Alignment`, `Cohesion`,
`GoalSeeking`, `Avoidance`, `Gradient` behaviors. Velocities clamped per config.

**Consensus engine:**
- Quorum + threshold configurable (default 67%)
- `Block` vote prevents passage regardless of approval rate
- Full vote history with timestamps

**Collective memory:** `Fact {content, topic, epistemic, confidence, contributors}`
indexed by topic — agents share knowledge no individual fully holds.

### How It Maps to Morgoth

| Morgoth Concept | Commune Equivalent |
|---|---|
| `pane.id` (UUID) | `AgentId` |
| `pane.role` ("claude"\|"terminal") | `AgentInfo.capabilities` |
| `pane.inbox[]` | `MessageQueue` per agent |
| `mq_send(panes, from, to, kind, payload)` | `commune.express(intent)` |
| `task_add` / `task_done` MQ kinds | `Intent::Delegate` / `Intent::Report` |
| pane trust (implicit) | `TrustManager` with accuracy tracking |
| Phase 27 task queue | `ConsensusEngine` for dispatch voting |
| `write_manifest()` | `commune.register(agent_info)` |
| scrollback search | `CollectiveMemory.recall(topic)` |

### Phase 28 Possibility: Commune-Backed MQ

Replace the hand-rolled `mq_send/mq_process_external/mq_persist` with Commune.
Panes become registered agents; task dispatch becomes `Intent::Delegate`; idle
detection becomes swarm coordination. Trust scores would gate which panes receive
which kinds of work.

---

## Part 2: Full Ecosystem Inventory

### Tier 1 — High Relevance to Morgoth

| Library | Description | Key Integration |
|---|---|---|
| **commune** | Intent-based multi-agent comms with trust, epistemic, swarm, consensus, collective memory | Replace/augment Phase 25/26 MQ; panes as agents |
| **daemon** | Autonomous agent runtime: heartbeat cycle, persistent goals, tool registry, lifecycle hooks, snapshot/restore | Panes as daemon agents with goals and tool access |
| **engram** | 4-tier memory (Instant/Episodic/Semantic/Procedural), reconstruction-based recall, strategic forgetting, Anamnesis query language | Replace Phase 18 JSON session persistence with proper memory |
| **omen** | Planning + reasoning: goal decomposition, belief revision (AGM), causal reasoning, counterfactuals, risk assessment | Task queue intelligence — Morgoth as planner, not just dispatcher |
| **covenant** | Human-agent collaboration: shared understanding, boundary enforcement, graceful handoffs, trust dynamics | Gate which tasks Claude panes can accept; approval flows |
| **oracle** | Explainability: reasoning traces, counterfactuals, evidence attribution, multi-level explanations | Explain task dispatch decisions in monitor pane |

### Tier 2 — Medium Relevance

| Library | Description | Key Integration |
|---|---|---|
| **gnosis** | Experience-based skill development, reflection, meta-learning, growth tracking | Claude panes learn user patterns over sessions |
| **chorus** | Resonance between minds — genuine co-creation, mutual transformation, emergence | Multi-Claude pane collaboration model |
| **hades** | Liminal infrastructure: threshold crossings, cost acknowledgment, mourning | Pane death and session ending handled with care |
| **nemesis** | Cosmic rebalancing: threshold monitoring, hubris detection, prevent resource hoarding | Cap compute/tokens consumed by any single pane task |
| **theoros** | Witnessing: sacred gaze, presence that transforms, testimony | Monitor pane as witness to pane activity |
| **aegis** | Security: identity verification, execution containment, memory integrity, audit log | Validate shells, contain untrusted panes |

### Tier 3 — Low / Philosophical

| Library | Description | Notes |
|---|---|---|
| **anima** | Inner life, expression of inner states, resonance | Philosophical only |
| **aporia** | Productive uncertainty, acting despite not-knowing | Interesting for task uncertainty handling |
| **ate** | Broken epistemology, hallucination modeling | Understanding Claude pane failures |
| **prometheus** | Transformative teaching, knowledge gift | Session onboarding flows |
| **morpheus** | Background processing, memory consolidation, dream logic | Background task models |
| **dionysus** | Ecstatic states, creative destruction, play | Not applicable |
| **echo** | Fragmented existence, discontinuous identity | Not applicable |

### Tier 4 — Not Applicable

| Library | Reason |
|---|---|
| **basilica** | HTTP web framework |
| **sigil-web / sigil-web-router / sigil-web-sys** | WASM/browser target |
| **sigil-kmp** | Kotlin Multiplatform |
| **anima, dionysus, echo, ate, aporia** | Purely philosophical / no operational API |

---

## Part 3: stdlib Functions Not Yet Used in Morgoth

From the full stdlib survey (~1,463 exposed functions):

### Immediately Usable

**Crypto** (relevant for task IDs, manifest signing):
- `blake3(data)` — fast content hashing
- `sha256(data)`, `hmac_sha256(key, data)` — message authentication
- `secure_random_bytes(n)`, `secure_random_hex(n)` — better UUIDs

**Text processing** (relevant for scrollback search, task parsing):
- `word_wrap(text, width)` — for overlay rendering
- `levenshtein(a, b)` — fuzzy task matching
- `regex_match(pattern, text)`, `regex_find_all(pattern, text)` — pattern search
- `extract_urls(text)`, `extract_mentions(text)` — pane output parsing

**Channels** (cleaner inter-pane comms):
- `channel_new()`, `channel_send(ch, msg)`, `channel_recv(ch)` — replace fake pipes
- `channel_recv_timeout(ch, ms)`, `channel_try_recv(ch)` — non-blocking variants

**Actors** (foundation for Commune integration):
- `spawn_actor(fn)`, `send_to_actor(actor, msg)`, `recv_from_actor(actor)` — actor model

**Swarm** (multi-Claude coordination):
- `swarm_create_agent(id, caps)`, `swarm_send_message(from, to, msg)`
- `swarm_find_agents(capability)` — find idle Claude panes by capability
- `swarm_consensus(topic, agents)` — vote on task dispatch

**LLM** (Morgoth as orchestrator, not just passthrough):
- `llm_request(model, messages)`, `llm_with_tools(model, msgs, tools)`
- `llm_parse_tool_call(response)`, `llm_extract(text, schema)`

**Vector store** (semantic scrollback search):
- `vec_store_add(store, id, embedding)`, `vec_store_search(store, query_vec, k)`
- `vec_embedding(text)` — embed pane output for similarity search

**Timer/profiling**:
- `time_it(fn)` — profile render loops
- `timer_start()`, `stopwatch_*` — event loop timing

### Requires Infrastructure

- `Http·get/post` — remote task submission API
- `WebSocket·connect` — real-time remote pane management
- `Kafka` producer/consumer — durable pane event streaming
- `AMQP` — enterprise message routing

---

## Part 4: Commune Deep Dive — Integration Architecture

### Proposed: Pane-as-Agent Model

```
Morgoth (Commune host)
├── Commune {
│   ├── AgentRegistry
│   │   ├── pane-0: terminal {trust: 0.9, caps: ["shell"]}
│   │   ├── pane-1: claude   {trust: 0.7, caps: ["analysis", "code"]}
│   │   └── pane-2: monitor  {trust: 1.0, caps: ["observe"]}
│   ├── Channels
│   │   ├── "system"     — PubSub, resize/shutdown events
│   │   ├── "tasks"      — RequestResponse, task delegation
│   │   └── "telemetry"  — Stream, continuous output
│   ├── CollectiveMemory — shared scrollback knowledge base
│   ├── ConsensusEngine  — vote on multi-pane task distribution
│   └── TrustManager     — track Claude pane accuracy over time
└── MessageQueue per pane (replaces inbox[])
```

### Task Dispatch via Commune

Instead of the Phase 27 auto-dispatch loop (checking idle ticks), Commune enables:

1. User runs `morgoth-task add "refactor auth module"`
2. Morgoth creates `Intent::Delegate { task, constraints: ["code", "analysis"] }`
3. `swarm_find_agents("code")` returns available Claude panes
4. Confidence-weighted selection: highest `trust_score × idle_factor`
5. `Intent::Delegate` delivered to selected pane's inbox
6. Claude pane completes work, sends `Intent::Report { status: Done, result }`
7. `commune.record_accuracy(pane_id, accurate: true)` updates trust
8. `ConsensusEngine` used when multiple panes need to agree on approach

### Epistemic Annotations in Practice

When Claude pane writes to collective memory:
- PTY output captured verbatim → `Epistemic::Observed` (high confidence)
- Claude's interpretation → `Epistemic::Inferred` (trust-weighted)
- Cross-pane forwarded info → `Epistemic::Reported` (decayed confidence)
- Conflicting outputs between panes → `Epistemic::Contested` (triggers resolution)

---

## Part 5: Recommended Roadmap

### Phase 28: Commune Foundation
Replace hand-rolled MQ with Commune. Panes register as agents. Task delegation via
`Intent::Delegate`. Trust tracking from task outcomes.

### Phase 29: Engram Memory
Replace Phase 18 JSON session with Engram's 4-tier system. Episodic memory for
command history. Semantic memory for project patterns. Procedural memory for
frequently-used workflows. Anamnesis query language for recall.

### Phase 30: Omen Planning
Morgoth as a planner, not just a dispatcher. Task decomposition — "refactor auth"
becomes subtasks assigned to multiple Claude panes. Belief revision when subtasks
fail. Counterfactual reasoning for retry strategies.

### Phase 31: Daemon Panes
Claude panes become Daemon agents with heartbeat cycles, persistent goals, and
tool registries. A daemon pane can autonomously pursue a goal across multiple
sessions without requiring user re-prompting.

### Phase 32: Oracle + Covenant
Oracle provides explanations in the monitor pane for why tasks were dispatched as
they were. Covenant gates high-risk operations (file deletion, git push, shell
commands) behind configurable human approval thresholds.

---

*End of survey. See morgoth/LESSONS-LEARNED.md for implementation lessons.*
