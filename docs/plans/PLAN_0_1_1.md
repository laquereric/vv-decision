# PLAN_0_1_1 — `vv-decision` epistemic schemas

> *Adds **epistemic schemas** — a small declarative file (typically
> 1–4 KB of YAML or JSON) that defines a deliberation's *verified
> domains*, *knowledge gaps*, and *tripwires* — as a first-class,
> optional input to `deliberate(...)`. Inspired by the clinical-AI
> finding that a 2KB epistemic schema reduced hallucinations by
> ~60% relative to baseline GPT-4 and outperformed a full RAG
> pipeline on the same task at a fraction of the latency and cost
> (see `docs/research/DecisionContext.md`). v0.1.1 is **purely
> additive** on v0.1.0's pinned contract: schemas are optional,
> the old kwarg shape still resolves, and existing callers see no
> behavior change. The bet: the layer that owns the **forward-
> acting reasoning loop** is also the layer that should carry
> structured uncertainty into the model call.*

## Anchors

| Anchor | Where | Role |
|---|---|---|
| `docs/research/DecisionContext.md` (parent repo) | `../../../../docs/research/DecisionContext.md` | The research note that motivates this release. Documents the 2KB-file finding and the verified-domains / knowledge-gaps / tripwires schema shape this PLAN imports verbatim as the v0.1.1 contract. |
| `docs/research/DecisionLayer.md` (parent repo) | `../../../../docs/research/DecisionLayer.md` | The original architectural finding behind this gem. Epistemic schemas slot into the "context" + "reasoning" boxes of the forward-acting flow — they bound the deliberation, they do not replace it. |
| `docs/plans/PLAN_0_1_0.md` | this directory | The v0.1.0 baseline. v0.1.1 extends the pinned surface additively — no v0.1.0 contract item moves. |
| `vendor/vv-memory/docs/plans/PLAN_0.2.0.md` | sibling | `Vv::Memory::Conformer::Extractor` interface. v0.1.1's `DecisionExtractor` gains new `vvdec:` predicates (`bounded_by`, `verified_domain`, `knowledge_gap`, `tripwire_fired`) but the extractor class + revision string change is **versioned** (revision bumps to `"vv-decision/v0.1.1/DecisionExtractor"`). |
| `vendor/vv-graph/docs/plans/PLAN_0.13.0.md` | sibling (transitive) | `Vv::Graph::Scope` + the SPARQL surface — unchanged in v0.1.1. |

## Current state baseline (2026-05-26)

v0.1.0 ships the `deliberate(scope:, context:, provenance_id:,
&block)` entrypoint with the `recall` / `consider` / `reason_with`
/ `decide!` flow, the `Vv::Decision::Decision` AR aggregate root,
the `DecisionExtractor` Conformer subclass, and the four read-side
traversal methods. Hallucination-mitigation is implicit — the
operator chooses the SPARQL queries, the operator chooses the
options to `consider`, the operator supplies the LLM completion.
The gem records the trace; it does not constrain the reasoning.

The research note (`DecisionContext.md`) reframes that. The
2KB-file finding shows that pre-generation epistemic boundaries
beat post-generation retrieval at hallucination reduction. The
finding is layer-specific: it belongs at the layer that
**invokes the model** — which, in this substrate, is the
operator's code running inside `ctx.reason_with(...)`. v0.1.1
gives that operator code a typed, persisted, queryable schema
to use.

## Architectural shape (delta from v0.1.0)

```
   v0.1.0 flow                                       v0.1.1 addition

   deliberate(scope:, context:, &block)              deliberate(scope:, context:,
       │                                                 epistemic_schema: schema, &block)
       ▼                                                 │
   ┌───────────────────┐                                 ▼
   │ DeliberationCtx   │                          ┌────────────────────────────────┐
   │   recall          │                          │ Vv::Decision::EpistemicSchema  │
   │   consider        │  ← bounded by   ───────  │   verified_domains: { ... }    │
   │   reason_with     │                          │   knowledge_gaps:   [ ... ]    │
   │   decide!         │                          │   tripwires:        [ ... ]    │
   └─────────┬─────────┘                          └────────────────────────────────┘
             │                                                  │
             ▼                                                  ▼
   ┌─────────────────────────────────────────────────────────────────────────────┐
   │ Tripwire interpreter (Phase C)                                              │
   │   - fires at ctx.recall    (query patterns)                                 │
   │   - fires at ctx.decide!   (option in knowledge_gap)                        │
   │   - fires at ctx.reason_with (model claim patterns)                         │
   │ Tripwire actions: :refuse_and_flag (raises TripwireFired)                   │
   │                   :append_confidence_score (annotates the Decision row)    │
   │                   :flag (records a Bronze decision_tripwire episode)       │
   └─────────────────────────────────────────────────────────────────────────────┘
             │
             ▼
   Bronze tier:  +1 new episode kind  "decision_tripwire"
   Aggregate:    +1 new column        epistemic_schema  (jsonb)
                 +1 new column        tripwires_fired   (jsonb, default [])
   Silver tier:  +4 new predicates    vvdec:bounded_by
                                      vvdec:verified_domain
                                      vvdec:knowledge_gap
                                      vvdec:tripwire_fired
```

**Nothing in the v0.1.0 surface moves.** Old callers (no
`epistemic_schema:` kwarg) get exactly the v0.1.0 behavior —
`epistemic_schema` column defaults to `{}`, `tripwires_fired`
defaults to `[]`, the new vvdec: predicates emit zero triples
when the column is empty.

## Scope

### Phase A — `Vv::Decision::EpistemicSchema` value object

A small immutable value object loaded from YAML, JSON, or a Ruby
Hash. Validates shape at construction time. Frozen after build.

```ruby
schema = Vv::Decision::EpistemicSchema.load_yaml(<<~YAML)
  verified_domains:
    order_status:
      confidence: 0.94
    payment_flow:
      confidence: 0.91
  knowledge_gaps:
    - regulatory_compliance_post_2025
    - cross_jurisdiction_settlement
  tripwires:
    - pattern: exact_citation_without_source
      fires_on: reason_with
      action: refuse_and_flag
    - pattern: numeric_claim_no_audit
      fires_on: reason_with
      action: append_confidence_score
    - pattern: option_in_knowledge_gap
      fires_on: decide
      action: refuse_and_flag
YAML
```

#### Implementation

- `Vv::Decision::EpistemicSchema` — immutable struct-like value
  object backed by a frozen Hash. Constructors:
  - `.load_yaml(string)` — parses YAML, runs validation, freezes.
  - `.load_json(string)` — parses JSON, runs validation, freezes.
  - `.from_hash(hash)` — accepts a Hash with stringified keys, runs
    validation, freezes.
- Validation (raises `Vv::Decision::Errors::InvalidEpistemicSchema`):
  - `verified_domains` is a Hash<String, { "confidence" => Float
    in 0.0..1.0 }>.
  - `knowledge_gaps` is an Array<String>.
  - `tripwires` is an Array<Hash> with required keys `pattern:`
    (String), `fires_on:` (one of `"recall"`, `"reason_with"`,
    `"decide"`, `"consider"`), `action:` (one of
    `"refuse_and_flag"`, `"append_confidence_score"`, `"flag"`).
  - Total serialized size ≤ 16 KB (a soft cap; the research note's
    2 KB is the *common* case, not a constraint). Larger schemas
    raise `Errors::EpistemicSchemaTooLarge` — operators with
    bigger schemas should split per-scope.
- Methods:
  - `#verified_domains` → frozen Hash.
  - `#knowledge_gaps` → frozen Array.
  - `#tripwires_for(stage)` → frozen Array of tripwire hashes
    matching `fires_on == stage.to_s`.
  - `#to_h` → deep-dup of the underlying Hash (for round-tripping
    through the AR jsonb column).
  - `#==` / `#hash` / `#frozen?` — value semantics.
- No mutation surface. Schemas are immutable after load.

#### Exit criteria
- Spec: `EpistemicSchema.load_yaml(yaml_string)` returns a frozen
  schema; mutating its `to_h` does not mutate the schema.
- Spec: missing required keys raise `InvalidEpistemicSchema` with
  the offending key in the message.
- Spec: a 17 KB schema raises `EpistemicSchemaTooLarge`.
- Spec: `#tripwires_for(:recall)` returns only tripwires with
  `fires_on: "recall"`.
- Spec: round-trip — `EpistemicSchema.from_hash(schema.to_h) == schema`.

### Phase B — `deliberate(..., epistemic_schema:)` + persistence

Extends the v0.1.0 entrypoint additively.

```ruby
schema = Vv::Decision::EpistemicSchema.load_yaml(File.read("config/order_agent.epistemic.yml"))

decision = Vv::Decision.deliberate(
  scope:             session,
  context:           "user asked: should we cancel order 42?",
  epistemic_schema:  schema,
) do |ctx|
  ctx.schema  # => the EpistemicSchema; nil if the kwarg was omitted
  # ... existing v0.1.0 flow ...
end
```

#### Schema migration (additive)

```ruby
class AddEpistemicSchemaToVvDecisionDecisions < ActiveRecord::Migration[8.1]
  def change
    add_column :vv_decision_decisions, :epistemic_schema, :jsonb,
               null: false, default: {}
    add_column :vv_decision_decisions, :tripwires_fired, :jsonb,
               null: false, default: []
  end
end
```

The migration is additive. Existing rows backfill to `{}` / `[]`
trivially. SQLite uses `:json` (same as v0.1.0's other JSON columns).

#### Implementation

- `Vv::Decision.deliberate(scope:, context:, provenance_id: nil,
  epistemic_schema: nil, &block)`:
  - If `epistemic_schema:` is non-nil, store its `#to_h` into the
    new `epistemic_schema` jsonb column on the `Decision` row.
  - Pass the schema (or `nil`) into the `DeliberationContext`.
- `Vv::Decision::DeliberationContext#schema` — reader returning
  the `EpistemicSchema` or `nil`. Stable handle for tripwire
  consultation inside the block.
- `Vv::Decision::Decision#epistemic_schema` — returns an
  `EpistemicSchema` reconstructed from the jsonb column via
  `EpistemicSchema.from_hash(...)`. Memoized. Returns `nil` if the
  column is empty (`{}`).
- `Vv::Decision::Decision#tripwires_fired` — returns the jsonb
  array as-is. Each entry: `{ "pattern" => …, "fires_on" => …,
  "action" => …, "at" => ISO8601, "detail" => freeform }`.

#### Exit criteria
- Spec: `deliberate(scope:, context:, &block)` (no `epistemic_schema:`)
  persists a `Decision` with `epistemic_schema == {}` and
  `tripwires_fired == []`. Existing v0.1.0 specs unchanged.
- Spec: `deliberate(scope:, context:, epistemic_schema: schema, &block)`
  persists `schema.to_h` in the column; `decision.epistemic_schema == schema`.
- Spec: `ctx.schema` inside the block returns the passed schema (or `nil`).
- Spec: `Decision#epistemic_schema` is memoized — repeated calls
  return the same frozen object.
- Spec: re-reading from the DB round-trips `EpistemicSchema` value equality.

### Phase C — tripwire interpreter

The interpreter consults the schema at each flow stage and applies
the configured action. Pattern matching is regex-based on the
relevant payload (query string for `recall`, prompt string for
`reason_with`, option symbol for `decide`, option + grounded_in
IRIs for `consider`).

#### Tripwire actions

| Action | Effect |
|---|---|
| `:refuse_and_flag` | Records a Bronze `decision_tripwire` episode, appends the entry to `decision.tripwires_fired`, then **raises `Vv::Decision::Errors::TripwireFired`** with the pattern + stage + detail. The outer `deliberate(...)` transaction rolls back (same shape as v0.1.0's block-raises semantics). The exception carries the partial `Decision` for inspection. |
| `:append_confidence_score` | Records a Bronze `decision_tripwire` episode, appends to `tripwires_fired`. Does **not** raise. The flow continues; the score is available via `decision.tripwires_fired.last["detail"]["confidence_score"]`. |
| `:flag` | Records a Bronze `decision_tripwire` episode, appends to `tripwires_fired`. Does not raise, does not annotate the Decision beyond the entry. Pure observability. |

Built-in patterns shipped with v0.1.1:

| Pattern | Stage | What it matches |
|---|---|---|
| `option_in_knowledge_gap` | `decide` | `decide!(option: opt)` where `opt.to_s` matches any entry in `schema.knowledge_gaps` (exact string OR regex if the gap entry starts with `/`). |
| `query_in_knowledge_gap` | `recall` | The query text matches a `knowledge_gaps` entry. |
| `exact_citation_without_source` | `reason_with` | The prompt contains a citation-like substring (matched by `/\[\d{4}\]\s+[A-Z][a-z]+/` or `/\(\d{4}\)\s+[A-Z]/`) and `grounded_in_iris` across the call is empty. |
| `numeric_claim_no_audit` | `reason_with` | The completion text (if provided at `reason_with` time) contains a numeric claim (`/\b\d+(\.\d+)?%?\b/`) and no `audit_url:` key is present in the schema's verified-domain metadata for the matching domain. |
| `unverified_domain_claim` | `reason_with` | The prompt mentions a domain string not in `verified_domains` and not in `knowledge_gaps`. Conservative: only fires if both lists are non-empty (operators with empty schemas opt out by omission). |

Operators may also register **custom** patterns by passing
`tripwires:` entries whose `pattern:` starts with `regex:` — the
remainder is compiled as a `Regexp` and matched against the
stage's primary payload.

#### Implementation

- `Vv::Decision::TripwireInterpreter` — stateless module with
  one entry point per stage:
  - `.check_recall!(ctx:, query:)` → returns the matched tripwire
    entries (possibly empty); the `DeliberationContext` applies
    the action.
  - `.check_reason_with!(ctx:, prompt:, completion:)` → same.
  - `.check_decide!(ctx:, option:, because:)` → same.
  - `.check_consider!(ctx:, option:, grounded_in_iris:)` → same.
- `DeliberationContext` calls the appropriate `check_*` before
  the v0.1.0 work for each stage. If no schema is present, the
  call short-circuits and returns `[]` (zero overhead).
- Action dispatch lives in `DeliberationContext`:
  - For each matched entry, append a Bronze `decision_tripwire`
    episode (kind: `"decision_tripwire"`; payload: `{ pattern:,
    stage:, action:, detail: }`) and an entry to
    `decision.tripwires_fired`.
  - If any entry has `action: "refuse_and_flag"`, raise
    `Vv::Decision::Errors::TripwireFired.new(entries:)` AFTER all
    bookkeeping for that stage completes. The outer transaction
    rolls back per v0.1.0 semantics — meaning the `tripwires_fired`
    column and the Bronze rows also roll back, which is desired:
    the tripwire fired but the deliberation never happened. The
    raised exception carries the entries for the operator's
    catch-and-record path (if they want the fact-of-tripwire to
    persist outside the rolled-back deliberation, they catch the
    exception, examine `e.entries`, and record an out-of-band
    Bronze episode themselves; the gem does not nest transactions).
- New Bronze episode kind: `"decision_tripwire"`. Added to the
  reserved-kinds constant `Vv::Decision::EPISODE_KINDS`.

#### Exit criteria
- Spec: a schema with `option_in_knowledge_gap` + `action: refuse_and_flag`;
  `ctx.decide!(option: :foo)` where `:foo` is in the gap raises
  `Errors::TripwireFired`; the outer block rolls back; no
  `decision_outcome` episode, no `decision_tripwire` episode
  (rolled back with the transaction); `e.entries.first["pattern"] == "option_in_knowledge_gap"`.
- Spec: a schema with `action: append_confidence_score` does NOT
  raise; the flow completes; `decision.tripwires_fired.size == 1`;
  the Bronze `decision_tripwire` episode is persisted.
- Spec: a schema with `action: flag` does NOT raise; the flow
  completes; `decision.tripwires_fired.size == 1`.
- Spec: `deliberate(...)` without an `epistemic_schema:` kwarg
  invokes zero tripwire checks (verified via a spy on the
  interpreter).
- Spec: custom `regex:`-prefixed patterns compile + match correctly.
- Spec: all five built-in patterns fire on the canonical positive
  case and do NOT fire on the canonical negative case.
- Spec: `Vv::Decision::EPISODE_KINDS` includes `"decision_tripwire"`.

### Phase D — `DecisionExtractor` v0.1.1 — new `vvdec:` predicates

The `DecisionExtractor` revision bumps from
`"vv-decision/v0.1.0/DecisionExtractor"` to
`"vv-decision/v0.1.1/DecisionExtractor"`. The new predicates emit
only when the corresponding column is non-empty — empty schemas
produce zero additional triples (backward-compatible Silver).

#### New predicates

```turtle
@prefix vvdec: <urn:vv-decision:annotation:> .

<urn:vv-decision:decision:42>
    vvdec:bounded_by         <urn:vv-decision:schema:sha256:abc123…> ;
    vvdec:verified_domain    "order_status" , "payment_flow" ;
    vvdec:knowledge_gap      "regulatory_compliance_post_2025" ;
    vvdec:tripwire_fired     <urn:vv-decision:tripwire:42:1> .

<urn:vv-decision:tripwire:42:1>
    vvdec:tripwire_pattern   "option_in_knowledge_gap" ;
    vvdec:tripwire_stage     "decide" ;
    vvdec:tripwire_action    "append_confidence_score" ;
    vvdec:tripwire_at        "2026-05-26T15:30:00Z"^^xsd:dateTime .
```

The `vvdec:bounded_by` IRI is a content-addressed identifier
derived from the schema's canonical-JSON SHA-256, so two decisions
sharing the same schema share the same `bounded_by` subject.
Operators querying "which decisions used this schema" do a
single SPARQL lookup against the IRI.

#### Implementation

- Extractor's `#revision` returns `"vv-decision/v0.1.1/DecisionExtractor"`.
- The v0.1.0 cursor in `vv-memory`'s Conformer state advances per
  `(scope, revision)` pair. Bumping the revision means the
  extractor re-processes existing decisions to backfill the new
  predicates — desired behavior (existing Silver gains the new
  predicates without manual reprocessing).
- The v0.1.0 emit list is unchanged. New triples are emitted when:
  - `epistemic_schema` jsonb column is non-empty → emit
    `vvdec:bounded_by` + per-verified-domain + per-knowledge-gap.
  - `tripwires_fired` jsonb column is non-empty → emit one
    `vvdec:tripwire_fired` IRI per entry + four scalar triples per
    tripwire subject.
- Schema-IRI minting:
  `Vv::Decision::EpistemicSchema#content_iri` returns
  `"urn:vv-decision:schema:sha256:#{Digest::SHA256.hexdigest(canonical_json)}"`.
  Canonical JSON = stable key ordering (sorted) + no whitespace.

#### Exit criteria
- Spec: a `deliberate(...)` with no schema → after `conform_now!`,
  none of the four new predicates appear (Silver is byte-identical
  to v0.1.0 except for the extractor-revision annotation).
- Spec: a `deliberate(...)` with a schema → after `conform_now!`,
  `vvdec:bounded_by` lands once, `vvdec:verified_domain` lands once
  per verified-domain key, `vvdec:knowledge_gap` lands once per gap.
- Spec: two decisions sharing the same schema have the same
  `vvdec:bounded_by` IRI.
- Spec: a tripwire that fired produces one `vvdec:tripwire_fired`
  IRI plus the four scalar predicates on it.
- Spec: bumping the extractor revision re-emits the new predicates
  for v0.1.0-era decisions on the next `conform_now!`
  (cursor-replay verified).

### Phase E — `bin/check`, docs, CHANGELOG

- `bin/check` — unchanged binary; the new specs run under the
  existing harness. The script's `vv-memory` and `vv-graph` checks
  do not move.
- `CHANGELOG.md` — `0.1.1 — (unreleased)` heading with the
  per-phase entries.
- `README.md` — add an "Epistemic schemas" section above the
  "Sketch of the surface" block. Cross-reference
  `docs/research/DecisionContext.md`. Show one end-to-end YAML
  example + the `deliberate(..., epistemic_schema:)` call.
- `CONSUMER_REQUIREMENT_MM.md` — note that `mm-server` should
  ship per-agent `*.epistemic.yml` files under
  `config/decision_schemas/` and load them at deliberate-time. The
  reserved `kind:` strings grow by one: `decision_tripwire`.
- `VERSION` → `0.1.1`.
- `docs/plans/PLAN_0_1_1.md` — this file. Update "Current state
  baseline" as phases land.

#### Exit criteria
- `bin/check` exits 0 against the canonical dev environment.
- The v0.1.0 integration spec still passes unchanged (additive proof).
- A new `epistemic_schema_integration_spec.rb` passes: full
  round-trip — schema load → `deliberate` with schema → tripwire
  fires → schema persisted in column → re-read via `Decision#epistemic_schema`
  → `conform_now!` → new vvdec: predicates land in Silver.
- `CHANGELOG.md` `0.1.1` heading drops `(unreleased)`.

## Out of scope for v0.1.1

- **LLM invocation inside `deliberate(...)`.** Still deferred to
  v0.2.0+. v0.1.1's tripwires fire on operator-supplied payloads
  (the same payloads v0.1.0 already accepts). The schema does not
  itself invoke or constrain a model — it constrains the operator's
  *recording* of the model call.
- **Automated schema generation from evaluation logs.** The
  research note describes a future where schemas are continuously
  generated from observed hallucinations. v0.1.1 ships static
  loaders (`load_yaml` / `load_json` / `from_hash`) only. The
  generation pipeline is a separate concern, likely a v0.3.0+
  deliverable or a sibling gem.
- **Schema inheritance / composition.** A `parent:` field that lets
  a per-decision schema extend a per-scope baseline. Considered for
  v0.1.1 and rejected — adds a non-trivial validation matrix
  (cycle detection, override precedence) for a feature no consumer
  has asked for. Lands in v0.2.0 if a consumer asks.
- **Schema validation against the SHACL surface of `vv-graph`.**
  Decision-pattern shaping (using SHACL to validate well-formed
  decisions) was already deferred in v0.1.0's "Out of scope" list.
  An epistemic schema is NOT a SHACL shape — it constrains the
  *flow*, not the *triples*. The two surfaces stay separate.
- **Class-level analytical facades, causal traversal, action
  emission, Curator (Gold) integration, `Vv::Memory.recall(...)`
  facade integration, multi-scope queries.** All still deferred per
  v0.1.0's "Out of scope" list.

## v0.1.1 contract additions (frozen at release)

| Surface | Shape | Mutability |
|---|---|---|
| `Vv::Decision.deliberate(scope:, context:, provenance_id: nil, epistemic_schema: nil, &block)` | module method — adds the `epistemic_schema:` kwarg | **Additive on v0.1.0.** Kwarg defaults to `nil`; v0.1.0 call shape resolves unchanged. |
| `Vv::Decision::EpistemicSchema.load_yaml` / `.load_json` / `.from_hash` | class methods | **Pinned.** |
| `Vv::Decision::EpistemicSchema#verified_domains` / `#knowledge_gaps` / `#tripwires_for` / `#to_h` / `#content_iri` | instance methods on the value object | **Pinned.** |
| `Vv::Decision::DeliberationContext#schema` | instance method — returns the schema or `nil` | **Pinned.** |
| `Vv::Decision::Decision#epistemic_schema` / `#tripwires_fired` | instance methods on the AR row | **Pinned.** `#epistemic_schema` returns `nil` for v0.1.0-era rows (empty jsonb). |
| `epistemic_schema` + `tripwires_fired` jsonb columns on `vv_decision_decisions` | schema | **Pinned column names.** Default `{}` and `[]` respectively. |
| Bronze episode `kind:` string `"decision_tripwire"` | convention | **Pinned.** Added to `Vv::Decision::EPISODE_KINDS`. |
| Tripwire actions: `"refuse_and_flag"` / `"append_confidence_score"` / `"flag"` | enum | **Pinned strings.** Additive new actions allowed in 0.1.x; existing strings cannot change semantics. |
| Tripwire stages: `"recall"` / `"reason_with"` / `"decide"` / `"consider"` | enum | **Pinned strings.** |
| Built-in tripwire patterns: `option_in_knowledge_gap` / `query_in_knowledge_gap` / `exact_citation_without_source` / `numeric_claim_no_audit` / `unverified_domain_claim` | conventions | **Pinned names.** Their regex/heuristic implementations are pinned at v0.1.1 and may tighten in v0.1.x ONLY in a strictly-additive direction (a previously-firing case continues to fire; a previously-quiet case may begin to fire). False-positive corrections that *remove* firing behavior wait for v0.2.0. |
| `vvdec:bounded_by` / `vvdec:verified_domain` / `vvdec:knowledge_gap` / `vvdec:tripwire_fired` (+ `vvdec:tripwire_pattern` / `vvdec:tripwire_stage` / `vvdec:tripwire_action` / `vvdec:tripwire_at`) | RDF predicates | **Pinned IRIs.** |
| `urn:vv-decision:schema:sha256:<hex>` IRI scheme for `vvdec:bounded_by` subjects | convention | **Pinned.** |
| `Vv::Decision::Errors::TripwireFired` / `InvalidEpistemicSchema` / `EpistemicSchemaTooLarge` | exception classes | **Pinned class names.** `TripwireFired#entries` returns an `Array<Hash>` of fired-tripwire entries. |
| `DecisionExtractor#revision` = `"vv-decision/v0.1.1/DecisionExtractor"` | string | **Bumped from v0.1.0.** Triggers cursor-replay across `(scope, revision)` pairs in `vv-memory`'s Conformer — desired, so existing decisions backfill the new predicates. |

The pinned v0.1.0 surface is unchanged. Every v0.1.0 contract row
still holds at v0.1.1.

## Risks

| Risk | Mitigation |
|---|---|
| Operators load enormous schemas (megabytes of verified domains) and the jsonb column bloats the `Decision` row. | The 16 KB cap at construction time. Operators with bigger schemas split per-scope or load a content-addressed schema once and store only the `content_iri` (a v0.2.0 add — see "Out of scope"). |
| Tripwire false positives block legitimate deliberations. Especially `unverified_domain_claim`, which is necessarily heuristic. | Conservative defaults: `unverified_domain_claim` only fires when BOTH `verified_domains` and `knowledge_gaps` are non-empty (operators opt in by populating both). The contract pins `:refuse_and_flag` raises but documents `:flag` and `:append_confidence_score` as the recommended starting points for new schemas. README's Quickstart shows the progressive-tightening pattern: start with `:flag`, observe the firing pattern in `tripwires_fired`, promote to `:refuse_and_flag` only after the operator trusts the regex. |
| Schema-content-IRI churn — a one-character change to a schema produces a new SHA-256, so historical queries "which decisions used schema X" become noisy as schemas evolve. | This is by design. The content-IRI IS the schema's identity at decision-time. Operators who want a *semantic* identity (a stable schema "name") add a `name:` field to the schema's top level — it does not affect `content_iri` (the SHA-256 is over the canonical-JSON of the schema's structural content). v0.1.1 ships the optional `name:` field; v0.2.0 adds a class-level `Vv::Decision.find_by_schema_name(...)` facade if a consumer asks. |
| The DecisionExtractor revision bump causes the Conformer to re-emit triples for every existing decision in every scope on the next `conform_now!`, which may be expensive for substrates with many decisions. | The revision bump is intentional — old decisions gain the new (zero-content) predicates and the cursor advances cleanly. For substrates worried about the re-emit cost, the gem documents the workaround: register a `Vv::Decision::DecisionExtractor::V0_1_0` shim (which the gem ships as a marker class) and the operator pins the older revision until they're ready. The shim is a v0.1.1 deliverable specifically to give substrates an escape hatch. |
| `tripwires_fired` jsonb column grows unbounded for long-lived Sessions accumulating many decisions, each with several fired tripwires. | One-per-row column on the Decision aggregate root — bounded by the number of tripwires that fire in *one* `deliberate(...)` call, which is bounded by the schema's tripwire count (typically <30 per the research note's 2 KB cap). Not a query-time concern. |
| The five built-in regex patterns are English-only and Latin-script-only. Substrates serving non-English deliberations get no benefit from `exact_citation_without_source` or `numeric_claim_no_audit`. | Documented. Operators with non-English deliberations supply their own `regex:`-prefixed patterns. v0.2.0 may ship language packs; v0.1.1 does not. |
| Pre-generation schemas — the research-note's mechanism of action — only constrain the model when injected into the prompt. v0.1.1's `reason_with(prompt:, completion:)` records the prompt + completion; the gem does not control prompt construction. | Documented as an operator responsibility. The Quickstart's worked example shows the prompt-construction helper that inlines the schema's `knowledge_gaps` + `verified_domains` summary into the system prompt. The gem provides `EpistemicSchema#to_prompt_preamble` (a small string-rendering method) as a convenience; using it is operator-optional. The gem's job is to *record* the schema-bounded deliberation; *applying* the schema to the model call is the operator's responsibility — same layering rule as v0.1.0's "the gem records the trace; the operator invokes the LLM." |
| Operators register custom `regex:`-prefixed patterns that compile to expensive regexes (catastrophic backtracking). | Document. v0.1.1 does NOT timeout-guard custom regex execution. Operators who ship untrusted-source schemas need their own validation pass; the gem assumes operator-authored schemas. Tracked as a v0.2.0 hardening item if a consumer ships untrusted schemas. |

## Acceptance signal

1. Phases A/B/C/D/E land with passing specs; the new
   `epistemic_schema_integration_spec.rb` is green.
2. The full v0.1.0 spec suite passes unchanged (additive proof —
   no v0.1.0 spec is touched).
3. `bin/check` green against the canonical dev environment.
4. `CHANGELOG.md` `0.1.1` heading drops `(unreleased)`.
5. `VERSION` → `0.1.1`.
6. `README.md` documents the `EpistemicSchema` value object, the
   `deliberate(..., epistemic_schema:)` kwarg, the three tripwire
   actions, and the five built-in patterns.
7. `CONSUMER_REQUIREMENT_MM.md` notes the recommended
   `config/decision_schemas/*.epistemic.yml` location and the
   new reserved `kind:` string `"decision_tripwire"`.
8. At least one `mm-server` agent path carries a real
   `epistemic_schema:` argument against the tagged 0.1.1 — proves
   the surface is usable end-to-end with a substrate consumer.
   (Tracked as the 0.1.2 / first-consumer-PR milestone if not
   landed concurrently with the tag.)

## Cross-references

- `../../../../docs/research/DecisionContext.md` — the research
  note that motivates this release. The 2KB-file finding; the
  verified-domains / knowledge-gaps / tripwires schema shape.
- `../../../../docs/research/DecisionLayer.md` — the original
  architectural finding for the gem.
- `./PLAN_0_1_0.md` — the v0.1.0 baseline. Every contract row
  there still holds at v0.1.1.
- `../../../vv-memory/docs/plans/PLAN_0.2.0.md` — Conformer +
  Extractor interface; v0.1.1's DecisionExtractor revision bump
  exercises the per-`(scope, revision)` cursor-replay path.
- `../../../vv-graph/docs/plans/PLAN_0.13.0.md` — `Vv::Graph::Scope`
  + SPARQL surface; unchanged in v0.1.1.
- `../../README.md` — this gem's README (gets an "Epistemic schemas"
  section in Phase E).
