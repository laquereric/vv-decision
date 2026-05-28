# Consumer requirements — `vv-learn` substrate

This file records the surface
[`vv-learn`](https://github.com/laquereric/magentic-market-ai/tree/main/vendor/vv-learn)
("LN" hereafter) consumes from `vv-decision` ("DS" hereafter). Mirrors the
pattern in
[`../vv-memory/CONSUMER_REQUIREMENT_LN.md`](../vv-memory/CONSUMER_REQUIREMENT_LN.md)
(LN's view of vv-memory) and
[`../vv-memory/CONSUMER_REQUIREMENT_DS.md`](../vv-memory/CONSUMER_REQUIREMENT_DS.md)
(DS's own view of vv-memory): upstream changes can be checked against a
written consumer expectation — **drift** between this file and the gem's
actual behaviour signals work that needs to land in both repos lockstep.

This is LN's perspective, not the DS spec. LN consumes `Vv::Decision`
through one entrypoint — `Vv::Decision.deliberate` — and reads the
`Vv::Decision::Decision` aggregate it returns. Everything else DS does
(Bronze episode emission, the `vvdec:` Conformer extractor, Silver
promotion) is machinery LN relies on existing but never touches directly.

- LN repo: <https://github.com/laquereric/magentic-market-ai/tree/main/vendor/vv-learn>
- LN plan that introduced the dependency:
  [`vendor/vv-learn/docs/plans/PLAN_0_1_0.md`](https://github.com/laquereric/magentic-market-ai/tree/main/vendor/vv-learn/docs/plans/PLAN_0_1_0.md)
  — the minimum viable round-trip; names PREREQ-C against this gem.
- LN v0.2.0 plan (the replay surface):
  [`vendor/vv-learn/docs/plans/PLAN_0_2_0.md`](https://github.com/laquereric/magentic-market-ai/tree/main/vendor/vv-learn/docs/plans/PLAN_0_2_0.md)
  — names PREREQ-E against this gem.

## The carve-out — what this file does NOT cover

> **LN reaches the substrate's memory tier via two paths. This file is the
> INDIRECT path (through DS). The DIRECT path is out of scope here.**

```
   ┌────────────────────────────────────────┐
   │                vv-learn                 │
   └────┬───────────────────────────────┬───┘
        │ INDIRECT (this file)          │ DIRECT (out of scope here)
        │                                │
        ▼                                ▼
  ┌─────────────────┐             ┌─────────────────┐
  │  vv-decision    │             │  vv-memory      │
  │  ─────────────  │             │  ─────────────  │
  │  • deliberate   │────────────▶│  • TurnEpisode  │
  │  • Deliberation │  DS calls   │  • shacl_       │
  │    Context      │  record_    │    validate     │
  │  • Decision     │  episode    │    facade       │
  │    aggregate    │  for the 5  │  (covered in    │
  │  • EvidenceSlice│  decision_* │   vv-memory/    │
  │                 │  kinds      │   CR_LN.md)     │
  └─────────────────┘             └─────────────────┘
```

**In scope for this file (the indirect path):**

1. `Vv::Decision.deliberate(scope:, context:, &block)` — the forward-acting
   entrypoint LN wraps every model call in.
2. The `Vv::Decision::DeliberationContext` block surface
   (`#recall`, `#consider`, `#reason_with`, `#decide!`, `#decided?`).
3. The `Vv::Decision::Decision` aggregate's read-side traversal
   (`#decided?`, `#option`, `#evidence_slice`, `#reasoning_trace`,
   `#alternatives_considered`, `#trace_back`, `#impact`).
4. `Vv::Decision::EvidenceSlice` as the return type of `#recall` and the
   evidence accessors.
5. `Vv::Decision::EPISODE_KINDS` — so LN can exclude DS's own Bronze rows
   from its `Run`-scoped episode views.

**Explicitly out of scope (handled elsewhere):**

1. **`Vv::Memory::*` surfaces.** LN's *direct* consumption of vv-memory
   (`TurnEpisode`, `Scoped#shacl_validate`, its own `learn_*` episode
   kinds) is specified in
   [`../vv-memory/CONSUMER_REQUIREMENT_LN.md`](../vv-memory/CONSUMER_REQUIREMENT_LN.md),
   not here. LN declares **both** `vv-decision` and `vv-memory`; the two
   consumption shapes are intentionally separate files because they evolve
   at different speeds.
2. **The `vvdec:` Silver triples and `Vv::Decision::DecisionExtractor`.**
   LN reads the `Decision` aggregate (an AR row + its accessors); the
   Conformer extractor lifecycle that promotes `decision_outcome` episodes
   into `vvdec:` Silver triples is DS's private concern. LN never
   subclasses, registers, or introspects `DecisionExtractor`, and never
   calls `Vv::Decision.register_extractor!` — the Engine does that.
3. **DS's consumption of vv-memory.** That DS calls `scope.record_episode`
   for the five `decision_*` kinds, and how it pins vv-memory, lives in
   [`../vv-memory/CONSUMER_REQUIREMENT_DS.md`](../vv-memory/CONSUMER_REQUIREMENT_DS.md).
   Drift in the `record_episode` keyword set is captured there, not here.

If a surface needs to migrate from one path to the other, the migration
spec belongs in **both** files with a cross-link.

## How LN pins this gem

```ruby
# vv-learn/vv-learn.gemspec
spec.add_dependency "vv-decision", ">= 0.1.0"
```

The pin is intentionally **loose** at the major-zero level. LN is willing
to absorb any 0.1.x patch transparently. LN's v0.1.0 round-trip consumes
only the surfaces that ship in DS 0.1.0 (single `consider` … `decide!` per
`deliberate`). The pin moves to `>= 0.2.0` lockstep with the DS release
that ships the **nested-consider loop** (PREREQ-C) — see "Boundary items"
below. Until then, LN's runtime maps one `Vv::Learn::Run` to one
`Vv::Decision::Decision` with a single committed option.

LN's Engine `after_initialize` guard refuses to boot if `Vv::Decision`
isn't loaded or doesn't respond to `:deliberate`, with a verbatim hint
pointing at the prerequisite bundle.

## The layering rule — load-bearing

> **LN consumes DS for the reasoning loop; LN never re-implements DS's
> flow recording, and never reaches past DS into vv-graph.**

Concretely:

1. **One `Run` = one `Decision`.** LN's `Vv::Learn::Run` aggregate holds a
   reference to exactly one `Vv::Decision::Decision`. LN does not create
   `Decision` rows by hand (`Vv::Decision::Decision.new`); the only way LN
   produces one is by calling `Vv::Decision.deliberate`.
2. **Every model call is routed through the deliberate block.** LN's
   `ModelDispatcher` is constructed *inside* the `Vv::Decision.deliberate`
   block and records each model consultation via
   `ctx.reason_with(model:, prompt:, completion:)`. LN does not call an
   LLM outside a deliberate block and then retro-fit a Decision.
3. **Decision-flow Bronze episodes are DS's responsibility, not LN's.** LN
   never calls `scope.record_episode(kind: "decision_*")` itself; all five
   `Vv::Decision::EPISODE_KINDS` rows are emitted by `DeliberationContext`.
   LN emits its *own* lifecycle kinds (`learn_run_started`, etc., specified
   in the vv-memory CR_LN) directly, but never decision-shaped ones.
4. **LN does not declare `vv-graph`.** DS reaches vv-graph privately (its
   `#recall` and `Decision#evidence_slice` run `Vv::Graph::Sparql` against
   the scope's Silver graph). LN sees only the `EvidenceSlice` value
   object DS returns — never a `Vv::Graph::*` object. Direct `Vv::Graph::*`
   references under `lib/vv/learn/` are a layering violation.

**Why this rule.** Three reasons:

- **The reasoning loop is a first-class lifecycle DS owns.** DS exists
  precisely to make context → query → reason → decide → act an atomic,
  audited unit. If LN recorded its own decision episodes it would split
  that lifecycle across two gems and lose the single-transaction guarantee
  in `Vv::Decision.deliberate`.
- **Engine substitutability.** When DS changes how it talks to vv-memory
  or vv-graph (it already absorbed the vv-memory `StrategySelector.register`
  vs `ExtractorRegistry.unregister` API change), LN should not need a line
  of change. DS is LN's abstraction boundary onto the reasoning loop;
  reaching past it erases that value.
- **The author/committer distinction.** A `Decision` with `decided_at: nil`
  is an abandoned deliberation that DS persists for audit. LN's
  `Refusals::REGISTRY` predicates against `decision.decided?` — that
  invariant only holds if LN never fabricates Decision rows itself.

The corollary: **LN is encouraged to lean harder on DS surfaces over
time.** When LN wants something DS doesn't expose (replay, nested
considers), the correct move is to file a boundary item below, not to
reach around DS.

## Surfaces LN consumes

### `Vv::Decision.deliberate(scope:, context:, provenance_id: nil, &block)` → `Vv::Decision::Decision`

The forward-acting entrypoint. LN's `ModelDispatcher` runs inside the
block. What LN depends on:

- **Signature.** Keyword `scope:` (a record including `Vv::Memory::Scoped`),
  `context:` (non-blank string), optional `provenance_id:`, and a required
  block. Pinned.
- **Atomicity.** The whole flow (Decision row + every Bronze episode) is
  one transaction. If LN's block raises, everything rolls back and the
  exception propagates. LN's `learn_run_failed` row is committed in a
  *separate outer* transaction precisely to survive this rollback (see
  vv-memory CR_LN).
- **Return value.** A persisted `Vv::Decision::Decision`. If `ctx.decide!`
  ran, `decided?` is true; otherwise the row persists with
  `decided_at: nil` (abandoned deliberation). LN branches on
  `decision.decided?`, never on an exception, for the abandoned case.
- **Entry validation.** Raises `Vv::Decision::Errors::InvalidDeliberation`
  for nil scope, blank context, a scope not including `Vv::Memory::Scoped`,
  or a missing block. LN relies on these being raised *before* any episode
  is written.

What LN explicitly does NOT introspect:

- The order in which the `decision_context` episode is written relative to
  the `Decision.new` call.
- Whether `Decision` uses STI, a state machine, or a plain timestamp for
  the committed flag (it's a timestamp today — LN only calls `decided?`).

### `Vv::Decision::DeliberationContext` — the block surface

Yielded to the `deliberate` block. LN calls four of its methods:

| Method | LN's use | Pinned shape |
|---|---|---|
| `#recall(query:, depth: :silver)` | LN reads its evidence slice | Returns an `EvidenceSlice`; `depth: :silver` only in DS 0.1.0 — other depths raise `RecallDepthUnsupported` |
| `#consider(option:, grounded_in: nil, rejected_because: nil)` | LN registers each candidate option | `grounded_in` accepts an `EvidenceSlice`, anything responding to `#iris`, or an Array of IRI strings; returns `self` (chainable) |
| `#reason_with(model:, prompt:, completion: nil)` | LN's `ModelDispatcher` records each model consultation | DS does **not** invoke an LLM — LN supplies `completion:`; returns `self` |
| `#decide!(option:, because:)` | LN commits the chosen option | Only one `decide!` per block; a second raises `AlreadyDecided`; returns the `Decision` |

What LN depends on:

- **`#reason_with` does not call a model.** DS 0.1.0 is BYO-LLM — LN owns
  the model call and passes the completion in. This is load-bearing: LN's
  `ModelDispatcher` is the single place a token is spent, and it sits in
  LN, not DS. If DS ever starts invoking models itself, LN's refusal
  pre-flight (which gates token spend) is bypassed.
- **`#consider` is additive and order-preserving.** LN may call it N times
  before `decide!`; each appends to the decision's `alternatives`. A
  mid-block change of mind is expressed as `consider(rejected_because:)`
  on the prior option, then a fresh `consider` + `decide!`.
- **`#decide!` is terminal.** Exactly one commit per deliberate.

What LN explicitly does NOT introspect:

- That each method also appends a Bronze episode (LN knows it happens; it
  doesn't read those rows through the context).
- The `EvidenceSlice` internals beyond `#where`, `#iris`, `#count`,
  `#empty?`, `#each`, `#to_a`.

### `Vv::Decision::Decision` — read-side traversal

After `deliberate` returns, LN's `Run#decision` reads:

- `#decided?` / `#option` — LN's `Refusals::REGISTRY` and `Run`
  reconciliation branch on these.
- `#evidence_slice` — the union of grounding IRIs hydrated from live
  Silver. LN's `Run#evidence_slice` surfaces this (until LN's own
  `Vv::Memory.recall` delegation lands).
- `#reasoning_trace` — the stored `{model:, prompt:, completion:}` with
  symbolized keys. LN's `Run#contract_outcomes` reads this.
- `#alternatives_considered` — rejected options + re-hydrated evidence.
- `#trace_back` / `#impact` — timeline traversal. LN's v0.2.0
  reconciliation reads these; v0.1.0 uses them read-only for the health
  dashboard.

What LN depends on:

- These are **read-only** accessors with no side effects. LN calls them
  outside the deliberate transaction.
- **Retracted IRIs omit silently** from `evidence_slice` while the
  original IRIs stay in the JSON column for audit. LN's evidence reader
  tolerates a slice smaller than the stored IRI list.

What LN explicitly does NOT introspect:

- The SPARQL `evidence_for` runs, or the `vv_decision_decisions` column
  shape beyond the accessor surface above.
- The `decision_*_episode` FK columns directly — LN reaches episodes
  through vv-memory's `scope.memory_episodes`, not through DS's FKs.

### `Vv::Decision::EPISODE_KINDS` — the exclusion constant

LN's `Run`-scoped episode views exclude DS's own Bronze rows:

```ruby
scope.memory_episodes.where.not(kind: Vv::Decision::EPISODE_KINDS)
```

What LN depends on: the constant exists, is frozen, and enumerates exactly
the kinds DS emits (`decision_context`, `decision_query`,
`decision_consider`, `decision_reasoning`, `decision_outcome`). If DS adds
a sixth decision kind, this constant must include it or LN's view leaks
DS rows.

### `Vv::Decision::Errors::*` — the error vocabulary

LN rescues / asserts against `InvalidDeliberation`, `AlreadyDecided`, and
`RecallDepthUnsupported` by class. `MissingDependency` is DS's own boot
guard (LN has its own). `NoDecisionMade` is defined but not raised by DS
0.1.0 — LN does not rescue it (LN branches on `decided?` instead).

## Predicate-shaped capability advertisements

LN does **not** introspect `Vv::Decision::VERSION` to branch behaviour.
Capability questions are answered by predicate checks:

- `defined?(::Vv::Decision) && ::Vv::Decision.respond_to?(:deliberate)`
  — LN's Engine `after_initialize` guard. False ⇒ raise
  `Vv::Learn::Errors::MissingDependency` at boot. **✅ true as of
  vv-decision v0.1.0.**
- (PREREQ-C) a predicate that detects nested-consider support — exact
  shape TBD when DS 0.2.0's PLAN circulates it. LN's branch will be on the
  predicate, not on `VERSION`.
- (PREREQ-E) `::Vv::Decision.respond_to?(:replay!)` — LN's v0.2.0
  `replay!` delegates to it; absent ⇒ the replay restriction stays.

When a capability is missing, LN's Engine raises `MissingDependency` at
boot with a verbatim hint — not at first call. A partial bundle is a
configuration error, not a runtime degradation.

## Boundary items — open requests back to `vv-decision`

These are surfaces LN needs that don't yet exist in DS. Written as
C-prefixed to match the LN PLAN naming (PREREQ-C, PREREQ-E).

### PREREQ-C — nested-consider loop (DS 0.2.0)

**Status: ⛔ not yet shipped. DS is at v0.1.0.**

**Source:** LN PLAN_0_1_0 §"Out of scope for v0.1.0" and gemspec note;
LN PLAN_0_2_0 Phase A.

**The ask.** DS 0.1.0 records one `reasoning_payload` per Decision (the
last `reason_with` wins) and supports a single `decide!`. LN's eventual
multi-step programs make **several** model calls within one logical Run,
each grounded in its own evidence and each a distinct `consider`. PREREQ-C
is the ask for `deliberate` to accumulate **N** `reason_with` traces (not
just the last), so one `Decision` aggregate holds the full nested loop of
considers and reasonings before a single terminal `decide!`.

**Why this needs to land in DS, not LN.**

- The `Decision` aggregate is DS's; accumulating N reasoning traces is a
  schema + accessor change on `vv_decision_decisions`
  (`reasoning_payload` → a collection), which is DS's concern.
- LN faking it by emitting its own `decision_reasoning` episodes would
  violate layering rule (3) — decision-flow Bronze rows are DS's.

**Acceptance signal.** LN's multi-step program spec drives one `Run` /
one `Decision` through several `reason_with` calls and reads all of them
back via `decision.reasoning_trace` (or a pluralized accessor DS names).
LN's gemspec pin moves to `>= 0.2.0`.

**Sequencing.** PREREQ-C is the long pole. LN's v0.1.0 round-trip works
without it (one consider, one reason, one decide); v0.2.0's multi-step
programs block on it.

### PREREQ-E — `Vv::Decision.replay!(decision_id, model:)` (deferred)

**Status: ⛔ not yet shipped.**

**Source:** LN PLAN_0_2_0 §"replay!".

**The ask.** A class method that re-runs an existing Decision's reasoning
trace against a **new** model, returning a NEW `Decision` aggregate
grounded in the same evidence slice. LN's v0.2.0 `Vv::Learn.replay!`
delegates to it (LN wraps the new Decision in a new `Run`).

**Why this needs to land in DS, not LN.** The reasoning trace, the
evidence slice, and the Decision aggregate are all DS-owned. Replay is a
DS operation that happens to have an LN consumer; LN re-implementing it
would duplicate the deliberate transaction logic.

**Acceptance signal.** LN's `replay!` integration spec produces a second
`Decision` (new id, same `evidence_slice`, new `reasoning_trace`) and a
new `Run`. Until then LN's `replay!` raises a deferred-feature refusal.

## Behaviours LN does NOT depend on

Refactors that touch these should not need to coordinate with this repo:

- **`Vv::Decision.register_extractor!` and the Conformer wiring.** LN
  never calls it; the Engine does. How DS routes `decision_outcome`
  episodes through `DecisionExtractor` (and the `StrategySelector.register`
  vs `unregister` API churn noted in `deliberate.rb`) is opaque to LN.
- **The `vvdec:` namespace and triple fan-out.** LN reads the `Decision`
  aggregate, never the Silver triples DS's extractor emits.
- **`Decision#trace_back` causal vs timeline semantics.** v0.1.0 is
  timeline-shaped (prior decisions whose outcome predates this context);
  v0.2.0 adds the `vvdec:caused_by` causal chain. LN's health dashboard
  tolerates either — it does not assert causality in v0.1.0.
- **The `provenance_id` value object internals.** LN passes an opaque id
  through `deliberate(provenance_id:)` and does not introspect it.
- **`Vv::Decision::VERSION` as a branch point.** LN uses the
  predicate-shaped advertisements above.

## Engine — explicitly not LN's concern

The vv-graph engine underneath DS's `#recall` and `Decision#evidence_slice`
(currently reached via `Vv::Graph::Sparql`) **must not be referenced from
`vv-learn`**. LN declares no `vv-graph` dependency; its specs do not load
graph engine artifacts. If DS swaps how it queries Silver, LN should not
need a line of change — DS is that abstraction boundary.

## Versioning expectation

- LN tracks DS at the major-zero level. Any 0.1.x patch is absorbed
  silently as long as the surfaces in "Surfaces LN consumes" keep their
  pinned contract.
- A breaking change to `Vv::Decision.deliberate`, `DeliberationContext`,
  the `Decision` accessor surface, or `EPISODE_KINDS` requires a
  coordinated LN release: DS's CHANGELOG names the breaking change; LN's
  gemspec pin tightens in the same PR (or the next LN tag).
- When PREREQ-C lands (DS 0.2.0), LN's pin moves to `>= 0.2.0`; the
  Engine guard's predicate checks remain version-independent.

## Drift signals

Conditions under which this file is **wrong** about reality and needs an
update (or a coordinated fix):

1. **`Vv::Decision.deliberate`'s keyword set changes** (`scope:`,
   `context:`, `provenance_id:`). LN's `ModelDispatcher` construction site
   breaks.
2. **`#reason_with` starts invoking an LLM itself.** LN's token-spend
   refusal pre-flight assumes the model call lives in LN; DS calling a
   model bypasses it. This is the highest-severity drift.
3. **`#decide!` allows more than one commit, or stops raising
   `AlreadyDecided`.** LN's one-Run-one-Decision invariant breaks.
4. **The `Decision` read accessors change shape** — e.g. `reasoning_trace`
   stops symbolizing keys, `evidence_slice` stops returning an
   `EvidenceSlice`, or `decided?` becomes a state-machine query. LN's
   `Run#contract_outcomes` / `Run#evidence_slice` break.
5. **`EPISODE_KINDS` gains a kind not in LN's exclusion list**, leaking
   DS Bronze rows into LN's `Run`-scoped episode views.
6. **`RecallDepthUnsupported` is removed before `Vv::Memory.recall`
   lands**, changing how `recall(depth: :gold)` fails. LN's recall callers
   assume the raise until the delegation ships.

## Last reviewed

2026-05-28 against vv-decision v0.1.0 (`lib/vv/decision/deliberate.rb`,
`lib/vv/decision/deliberation_context.rb`, `app/models/vv/decision/decision.rb`)
and vv-learn's pins (`vv-learn.gemspec`, `lib/vv/learn/engine.rb`). PREREQ-C
and PREREQ-E remain open; LN pin is `>= 0.1.0`.
