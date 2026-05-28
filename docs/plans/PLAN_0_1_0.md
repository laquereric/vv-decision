# PLAN_0_1_0 — `vv-decision` first shippable release

> *Stands up the `vv-decision` gem as the **third concern above
> memory**: the agent's reasoning loop as a first-class lifecycle.
> v0.1.0 ships the **minimum viable aggregate** — a `Decision` AR
> aggregate root, the `deliberate(context:, &block)` entrypoint,
> a `DecisionExtractor` (Conformer subclass) emitting `vvdec:`
> predicates, and four read-side traversal methods. The
> precedent-search / impact-pattern / policy-check facades and
> the Curator integration wait until v0.2.0+ once at least one
> consumer (mm-server) drives requirements. The bet: get the
> `deliberate → record → extract → recall` round-trip right
> first; defer the analytical surfaces until a consumer asks.*

## Anchors

| Anchor | Where | Role |
|---|---|---|
| `docs/research/DecisionLayer.md` (parent repo) | `../../../../docs/research/DecisionLayer.md` | The architectural finding that motivates this gem. Three-layer separation; decisions are flows, not triples. The aggregate-root + DecisionExtractor pattern is sourced from there. |
| `vendor/vv-memory/docs/plans/PLAN_0.1.0.md` | sibling | Bronze + Silver substrate. `Vv::Memory::Scoped#record_episode` is the integration point for decision-flow episodes. Hard dependency: `vv-memory >= 0.1.0`. |
| `vendor/vv-memory/docs/plans/PLAN_0.2.0.md` | sibling | `Vv::Memory::Conformer::Extractor` interface — the integration point for `Vv::Decision::DecisionExtractor`. Hard dependency: `vv-memory >= 0.2.0`. |
| `vendor/vv-memory/docs/plans/PLAN_0.4.0.md` | sibling | `Vv::Memory.recall(scope:, query:)` retrieval facade. Sketch only at v0.1.0 of *this* gem; v0.1.0 ships with a thinner Silver-only recall (see Phase C). |
| `vendor/vv-graph/docs/plans/PLAN_0.13.0.md` | sibling (transitive) | `Vv::Graph::Scope` value object for cross-graph operations. Used by the read-side aggregate methods. |
| `vendor/vv-graph/CONSUMER_REQUIREMENT_VV.md` | sibling | Boundary item B4 records the layering-correction ask back to vv-graph's PLAN_0.14.0 — this gem is the new home for the decision lifecycle. |
| [`semantica-agi/semantica`](https://github.com/semantica-agi/semantica) | upstream | The Python project whose decision-intelligence DSL motivated PLAN_0.14.0. Vocabulary inspiration; we deliberately do NOT adopt its decision-as-data framing. |

## Current state baseline

**2026-05-28 — v0.1.0 fully implemented (Phases A–F landed).**
Suite: 42 examples, 0 failures against the live `sqlite-sparql`
engine. The `deliberate → conform → recall →
checkpoint/evict/hydrate` round-trip passes end-to-end.

- Phase A ✅ skeleton + Engine + 5 error classes.
- Phase B ✅ `Decision` AR model + migration `20260525000001`.
- Phase C ✅ `deliberate` + `DeliberationContext` + `EvidenceSlice`
  + `EPISODE_KINDS`.
- Phase D ✅ `DecisionExtractor` + boot-time registration.
- Phase E ✅ five read-side traversal methods.
- Phase F ✅ integration spec + `bin/check` + CHANGELOG.

**API reconciliation (Phase D).** This plan's §Phase D sketched
registration via `Vv::Memory::Conformer::ExtractorRegistry` with
an `.unregister(extractor_class)` opt-out. vv-memory actually
shipped (v0.2.2, CR_DS B1 option A) a different surface:
`Vv::Memory::Conformer::StrategySelector.register(kind:,
extractor_class:)` keyed by episode kind, with **no per-class
unregister**. The implementation uses the shipped surface;
`Vv::Decision.register_extractor!` wraps the
`StrategySelector.register(kind: "decision_outcome", ...)` call
and runs in the Engine's `after_initialize`. Operators who want
to suppress decision triples thread a custom `StrategySelector`
(CR_DS B1 option B) rather than calling an unregister API.

---

*Original baseline (2026-05-25):* `vendor/vv-decision/` contained
only `README.md` (placeholder pointing at
`docs/research/DecisionLayer.md` plus the three-layer sidebar). No
gem skeleton, no Gemfile, no specs, no Engine, no `VERSION`.
v0.1.0 was a greenfield build.

The substrate (`server/`) currently records decision-like events
as ad-hoc Bronze episodes via `Vv::Memory::Scoped#record_episode`
with operator-chosen `kind:` strings. There is no aggregate root,
no flow-shaped persistence, and no Silver-side `vvdec:` namespace
— the decision provenance is implicit in the ordering of unrelated
Bronze rows. v0.1.0 of *this* gem is the surface that makes the
flow explicit and queryable.

The research note's open questions (1) (naming) and (2) (repo
shape) are answered by the directory's existence:
**`vv-decision`** (singular, matching the `vv-memory` verb-shaped
pattern) and **`vendor/vv-decision/`** path-vendored under the
monorepo.

## Architectural shape (frozen at v0.1.0)

```
                                              ┌──────────────────────────┐
                  ┌─── deliberate(context:) ─→│ Vv::Decision.deliberate  │
   request path                               └────────────┬─────────────┘
                                                           │
                            ┌──────────────────────────────┼──────────────────────────────┐
                            ▼                              ▼                              ▼
            ┌────────────────────────────┐  ┌────────────────────────────┐  ┌────────────────────────────┐
            │ ctx.recall(query:)         │  │ ctx.consider(option:,      │  │ ctx.decide!(option:,       │
            │   → Silver SPARQL query    │  │   grounded_in:)            │  │   because:)                │
            │   (v0.1.0: Silver-only)    │  │   → in-memory record       │  │   → commit + persist       │
            └─────────────┬──────────────┘  └─────────────┬──────────────┘  └─────────────┬──────────────┘
                          │                               │                               │
                          ▼                               ▼                               ▼
            ┌──────────────────────────────────────────────────────────────────────────────────────────┐
            │ Bronze — one or more Vv::Memory::Episode rows per deliberate(...) call                   │
            │   kind: "decision_context" / "decision_query" / "decision_consider" /                    │
            │         "decision_reasoning" / "decision_outcome"                                        │
            │ + one Vv::Decision::Decision AR row (the aggregate root) holding back-references        │
            └────────────────────────────┬─────────────────────────────────────────────────────────────┘
                                         │ (operator runs scope.conform_now! later, OR
                                         │  Vv::Decision::DecisionExtractor runs inline if configured)
                                         ▼
            ┌──────────────────────────────────────────────────────────────────────────────────────────┐
            │ Silver — typed triples in the scope's named graph                                        │
            │   <decision:42> rdf:type vvdec:Decision ;                                                │
            │                 vvdec:context "..." ;                                                    │
            │                 vvdec:decided_option :hold ;                                             │
            │                 vvdec:reason "active dependency on order 17 not yet resolved" ;          │
            │                 vvdec:grounded_in <evidence:1> , <evidence:2> ;                          │
            │                 vvdec:alternative_to :cancel , :proceed .                                │
            │ + RDF-star annotations pinning each outcome triple back to the originating episode       │
            └──────────────────────────────────────────────────────────────────────────────────────────┘

   Gold — curated decision-pattern commitments         (v0.3.0+, out of scope; depends on vv-memory Curator)
   Action emission + completion callback               (v0.2.0+, out of scope)
   Vv::Decision.find_precedents / analyze_impact / check_policies (v0.2.0+, out of scope)
```

**Aggregate root = `Vv::Decision::Decision`.** One AR row per
`deliberate(...)` call. Carries:

- the scope (polymorphic — same shape as `Vv::Memory::Episode`),
- the operator-supplied `context` string,
- the resolved `decided_option` symbol + `because` string,
- the considered-and-rejected `alternatives` (array of hashes),
- back-references to the originating `Vv::Memory::Episode` rows
  (`decision_context_episode_id`, `decision_outcome_episode_id`,
  plus a `has_many :memory_episodes, through: ...` association
  for the full flow),
- `decided_at` timestamp,
- `reasoning_payload` JSON column for the optional
  `ctx.reason_with(model:, prompt:)` step's prompt/completion
  pair.

**No new tier.** `vv-decision` reuses `vv-memory`'s Bronze (for
the flow episodes) and Silver (for the `vvdec:`-namespaced
triples). The novelty is the aggregate root + the DSL + the
extractor + the read-side traversal — not a new storage layer.

## Scope

### Phase A — gem skeleton + Engine

Bundler layout under `vendor/vv-decision/`:

```
vv-decision/
├── vv-decision.gemspec
├── Gemfile
├── lib/
│   ├── vv/decision.rb                   # top-level entry; requires the rest
│   ├── vv/decision/version.rb           # VERSION = "0.1.0"
│   ├── vv/decision/engine.rb            # Rails::Engine, isolate_namespace Vv::Decision
│   ├── vv/decision/railtie.rb           # eager-load + vv-memory dep check
│   ├── vv/decision/errors.rb            # MissingDependency, InvalidDeliberation, NoDecisionMade, etc.
│   ├── vv/decision/deliberation_context.rb  # Phase C
│   ├── vv/decision/decision_extractor.rb    # Phase D
│   └── vv/decision/decision.rb          # Phase B (AR model, re-opened in engine)
├── app/
│   └── models/
│       └── vv/decision/decision.rb      # canonical AR model
├── db/
│   └── migrate/
│       └── 20260525000001_create_vv_decision_decisions.rb
├── spec/
│   ├── spec_helper.rb
│   ├── support/
│   │   ├── rails_app.rb                 # minimal in-process Rails app w/ AS + Semantica
│   │   └── fake_scope.rb                # FakeSession AR fixture including Vv::Memory::Scoped
│   └── vv/decision/
│       ├── decision_spec.rb             # Phase B
│       ├── deliberation_context_spec.rb # Phase C
│       ├── decision_extractor_spec.rb   # Phase D
│       ├── traversal_spec.rb            # Phase E
│       └── deliberate_integration_spec.rb  # Phase F (acceptance signal)
├── bin/check                            # one-shot pre-release script
├── CHANGELOG.md
├── README.md                            # already present; Phase F expands
├── CONSUMER_REQUIREMENT_MM.md           # Phase F
├── VERSION                              # 0.1.0
└── docs/
    └── plans/
        └── PLAN_0_1_0.md                # this file
```

#### Implementation
- `vv-decision.gemspec`:
  - `spec.required_ruby_version = ">= 3.4"`.
  - `spec.add_dependency "rails", ">= 8.1"`.
  - `spec.add_dependency "vv-memory", ">= 0.2.0"` (the Conformer
    Extractor interface is the integration point).
  - `spec.add_dependency "vv-graph", ">= 0.13.0"` (for
    `Vv::Graph::Scope` + the SPARQL-star read surface used by
    the read-side aggregate methods). Transitively pulled by
    `vv-memory` but declared explicitly so a tightening of this
    gem's surface is visible at gemspec-resolution time.
- `lib/vv/decision.rb` requires `version`, `errors`, `engine`
  (Engine lazy-loads the rest under Rails).
- `Engine`: `isolate_namespace Vv::Decision`;
  `config.eager_load_namespaces << Vv::Decision`.
- `Railtie` (in `engine.rb`): in `config.after_initialize`,
  verify both `Vv::Memory::Scoped` and
  `Vv::Memory::Conformer::Extractor` constants are defined.
  Raise `Vv::Decision::Errors::MissingDependency` with verbatim
  "bundle vv-memory 0.2.0+ alongside vv-decision" message
  otherwise.
- Spec scaffold mirrors `vv-memory`'s pattern — minimal
  in-process Rails app boots ActiveStorage, ActiveRecord (SQLite
  memory), the `Semantica` extension, and both engines'
  migrations before each suite.

#### Exit criteria
- `bundle install` from `vendor/vv-decision/` resolves clean.
- `bundle exec rspec` runs (zero specs acceptable for Phase A;
  the harness must boot).
- `require "vv/decision"` in a host Rails app with `vv-memory`
  0.2.0+ installed does **not** raise; with `vv-memory` < 0.2.0
  (or missing the Conformer Extractor constant) it raises
  `Vv::Decision::Errors::MissingDependency`.
- `VERSION` file present, `Vv::Decision::VERSION == "0.1.0"`.

### Phase B — `Vv::Decision::Decision` aggregate root

The AR aggregate root. One row per `deliberate(...)` call.
Polymorphic scope mirrors `Vv::Memory::Episode`'s shape so the
two tables join cleanly on `(scope_type, scope_id)`.

#### Schema

```ruby
create_table :vv_decision_decisions do |t|
  t.references :scope, polymorphic: true, null: false, index: true
  t.string  :context,           null: false                # operator-supplied prompt
  t.string  :decided_option,    null: true                 # symbol-as-string; null = NoDecisionMade
  t.text    :because                                       # human-readable rationale
  t.jsonb   :alternatives,      null: false, default: []   # SQLite: t.json — [{ option:, grounded_in_iris:, rejected_because: }, ...]
  t.jsonb   :reasoning_payload, null: false, default: {}   # { model:, prompt:, completion: } when ctx.reason_with was invoked
  t.bigint  :decision_context_episode_id                   # FK → vv_memory_episodes.id (kind: "decision_context")
  t.bigint  :decision_outcome_episode_id                   # FK → vv_memory_episodes.id (kind: "decision_outcome")
  t.datetime :decided_at,       null: true, index: true    # null until ctx.decide! commits
  t.string  :provenance_id                                 # optional caller-supplied idempotent-replay key
  t.timestamps
end
add_index :vv_decision_decisions, [:scope_type, :scope_id, :decided_at]
add_index :vv_decision_decisions, :provenance_id, unique: true, where: "provenance_id IS NOT NULL"
add_foreign_key :vv_decision_decisions, :vv_memory_episodes, column: :decision_context_episode_id
add_foreign_key :vv_decision_decisions, :vv_memory_episodes, column: :decision_outcome_episode_id
```

#### Model

```ruby
module Vv
  module Decision
    class Decision < ApplicationRecord
      self.table_name = "vv_decision_decisions"
      belongs_to :scope, polymorphic: true

      belongs_to :decision_context_episode,
                 class_name:  "Vv::Memory::Episode",
                 foreign_key: :decision_context_episode_id,
                 optional:    true
      belongs_to :decision_outcome_episode,
                 class_name:  "Vv::Memory::Episode",
                 foreign_key: :decision_outcome_episode_id,
                 optional:    true

      validates :context, presence: true

      scope :decided,    -> { where.not(decided_at: nil) }
      scope :since,      ->(t) { where("decided_at >= ?", t) }
      scope :for_option, ->(opt) { where(decided_option: opt.to_s) }

      def decided?
        !decided_at.nil?
      end

      def option
        decided_option&.to_sym
      end
    end
  end
end
```

No state machine. The `decided_at` timestamp doubles as the
"committed" flag — null means `deliberate(...)` was entered but
`ctx.decide!` was never called (the row exists as evidence of an
abandoned deliberation; raising `NoDecisionMade` is the alternative
considered but rejected — keeping the row preserves audit). Phase C
governs which path the block actually takes.

#### Exit criteria
- Spec: creating a `Decision` with `scope:`, `context:` persists; reload round-trips the JSONB columns.
- Spec: `provenance_id` uniqueness enforced.
- Spec: polymorphic `scope` association resolves back to the AR record.
- Spec: `decided`, `since`, `for_option` scopes return the expected subsets.
- Spec: `Decision#decided?` returns `false` until `decided_at` is set.

### Phase C — `Vv::Decision.deliberate(context:, &block)` + `DeliberationContext`

The consumer-facing entrypoint. Wraps a block in a
`DeliberationContext` that records flow episodes into the scope's
Bronze and persists a `Decision` row atomically with the flow.

```ruby
class Session < ApplicationRecord
  include Vv::Memory::Scoped
  vv_memory do
    silver_iri    -> { "urn:vv-memory:session:#{id}:silver" }
    checkpoint_on :explicit
    on_destroy    :retain
  end
end

session = Session.create!

decision = Vv::Decision.deliberate(scope: session, context: "user asked: should we cancel order 42?") do |ctx|
  evidence = ctx.recall(query: "order 42 status and dependencies")
  ctx.consider(option: :cancel,  grounded_in: evidence.where(predicate: "mm:status"))
  ctx.consider(option: :hold,    grounded_in: evidence.where(predicate: "mm:has_dependency"))
  ctx.consider(option: :proceed, grounded_in: evidence.where(predicate: "mm:has_committed_funds"))

  ctx.reason_with(model: :claude_opus_4_7, prompt: <<~PROMPT, completion: completion_text)
    Given the evidence above, which option is consistent with the user's stated goal?
  PROMPT

  ctx.decide!(option: :hold, because: "active dependency on order 17 not yet resolved")
end
# => Vv::Decision::Decision (persisted, decided)
```

#### Implementation

- `Vv::Decision.deliberate(scope:, context:, provenance_id: nil, &block)`:
  1. Open a database transaction.
  2. Append a Bronze `decision_context` episode via
     `scope.record_episode(kind: "decision_context", payload: { context: context, provenance_id: provenance_id })`.
  3. Build a `Vv::Decision::Decision.new(scope: scope, context: context, decision_context_episode: ep, provenance_id: provenance_id)`.
  4. Yield a `DeliberationContext` wrapping (decision, scope) to
     the block.
  5. If the block raises, the transaction rolls back — no Decision
     row, no episodes. The caller's exception propagates.
  6. After the block returns, if `ctx.decide!` was never called,
     persist the Decision row with `decided_at: nil` (the
     abandoned-deliberation case) and return it. Operator can
     inspect `decision.decided?` to branch.
  7. If `ctx.decide!` was called, the Decision row is already
     persisted (decide! commits inline so the outcome episode's
     `decision_id` back-reference is set); return it.
  8. Commit the transaction.

- `Vv::Decision::DeliberationContext`:
  - `#recall(query:, depth: :silver)` — **v0.1.0 thin recall.**
    Wraps `Vv::Graph::Sparql.select(sparql_for(query),
    graph: scope.memory_silver[:iri])` and returns a
    `Vv::Decision::EvidenceSlice` wrapping the result rows. The
    `query:` parameter is a plain SPARQL string in v0.1.0 — the
    DSL-shaped natural-language `query: "…"` → SPARQL translation
    is deliberately not shipped (operator writes their own
    SPARQL). Records a Bronze `decision_query` episode with the
    query text and result-row count.
    When `vv-memory` PLAN_0.4.0 ships, `depth:` accepts `:gold`
    (traverses Gold → Silver) and `:bronze` (replays Bronze
    timeline) by delegating to `Vv::Memory.recall(...)`. v0.1.0
    refuses `depth:` other than `:silver` with
    `Errors::RecallDepthUnsupported`.
  - `#consider(option:, grounded_in:, rejected_because: nil)` —
    appends to the Decision's `alternatives` array (in-memory
    until decide!/return commits). Records a Bronze
    `decision_consider` episode with `{ option:, grounded_in_iris:
    [...], rejected_because: }`.
  - `#reason_with(model:, prompt:, completion: nil)` — assigns
    the Decision's `reasoning_payload` JSON to
    `{ model:, prompt:, completion: }`. Operator supplies the
    completion string (the gem does **not** invoke an LLM in
    v0.1.0 — that's an operator responsibility; the gem just
    records the trace). Records a Bronze `decision_reasoning`
    episode.
  - `#decide!(option:, because:)` — assigns
    `decided_option = option.to_s`, `because = because`,
    `decided_at = Time.current` on the Decision; saves; appends
    a Bronze `decision_outcome` episode with the outcome payload
    and back-fills `decision_outcome_episode_id`. Returns the
    Decision. Calling `decide!` twice raises
    `Errors::AlreadyDecided` (mid-block changes of mind are
    expressed via `consider(rejected_because:)` on the prior
    option, then a fresh `consider` + `decide!` on the new one
    — but only one `decide!` may commit per `deliberate` call).

- `Vv::Decision::EvidenceSlice` — read-only value object wrapping
  the SPARQL result rows. Supports `#where(predicate:, subject:,
  object:)` (in-memory filter), `#iris` (array of subject IRIs),
  `#count`, and `#to_a` (raw row hashes). No mutation surface.

#### Exit criteria
- Spec: `Vv::Decision.deliberate(scope: …, context: "x") { |ctx| ctx.decide!(option: :a, because: "y") }` returns a persisted `Decision` with `decided_at != nil`, `decided_option == "a"`, `because == "y"`, and a paired `decision_context_episode` + `decision_outcome_episode`.
- Spec: a block that raises rolls back **all** state — no Decision row, no Bronze episodes.
- Spec: a block that exits without calling `decide!` persists a Decision row with `decided_at: nil`; `decision.decided? == false`.
- Spec: calling `decide!` twice inside one block raises `Vv::Decision::Errors::AlreadyDecided`.
- Spec: `ctx.recall(query: sparql_string)` returns an `EvidenceSlice` whose row count matches `Vv::Graph::Sparql.select(sparql_string, graph: silver_iri)[:results].size`; records a `decision_query` episode.
- Spec: `ctx.recall(query: ..., depth: :gold)` raises `Errors::RecallDepthUnsupported` in v0.1.0.
- Spec: `ctx.consider(option: :a, grounded_in: slice)` appends to `decision.alternatives` and records a `decision_consider` episode.
- Spec: `ctx.reason_with(model: :x, prompt: "y", completion: "z")` sets `decision.reasoning_payload == { "model" => "x", "prompt" => "y", "completion" => "z" }` and records a `decision_reasoning` episode.
- Spec: `provenance_id` uniqueness — a second `deliberate(scope:, context:, provenance_id: "same")` raises `ActiveRecord::RecordNotUnique` at outer-transaction commit.

### Phase D — `Vv::Decision::DecisionExtractor` (Conformer subclass)

Promotes the decision-flow Bronze episodes into Silver triples
using the `vvdec:` namespace. Subclasses
`Vv::Memory::Conformer::Extractor` to preserve vv-memory's
invariant that *the Conformer is the only Bronze → Silver path*.

The extractor is triggered the same way as any other extractor:
operator calls `scope.conform_now!` (or `conform_later!`). The gem
does **not** auto-trigger inside `deliberate(...)` — that would
couple forward-acting and backward-acting concerns. The flow:

```ruby
session.deliberate(...) { ... }   # ← only writes Bronze + the Decision aggregate
# ... later, in a background job or operator-triggered ...
session.conform_now!              # ← reads decision_* episodes → emits vvdec: triples
```

#### Vocabulary

`vvdec:` resolves to `urn:vv-decision:annotation:`. Predicates
emitted per decision:

```turtle
@prefix vvdec: <urn:vv-decision:annotation:> .

<urn:vv-decision:decision:42> a vvdec:Decision ;
    vvdec:context           "user asked: should we cancel order 42?" ;
    vvdec:decided_option    "hold" ;
    vvdec:because           "active dependency on order 17 not yet resolved" ;
    vvdec:decided_at        "2026-05-25T14:30:00Z"^^xsd:dateTime ;
    vvdec:grounded_in       <urn:mm:order:17> , <urn:mm:order:42> ;
    vvdec:alternative_to    "cancel" , "proceed" ;
    vvdec:reasoned_with     "claude_opus_4_7" .

# RDF-star annotation pinning the decision to the originating Bronze episode:
<< <urn:vv-decision:decision:42> a vvdec:Decision >>
    vvmem:fromEpisode <urn:vv-memory:episode:128> ;
    vvmem:extractedBy "vv-decision/v0.1.0/DecisionExtractor" ;
    vvmem:confidence  "1.0" .
```

The `vvmem:` annotations come from the parent Conformer's
annotation pass — the DecisionExtractor only emits the `vvdec:`
content; the wrapping provenance annotations land via the same
mechanism every Conformer extraction uses.

#### Implementation

```ruby
module Vv
  module Decision
    class DecisionExtractor < Vv::Memory::Conformer::Extractor
      VVDEC = "urn:vv-decision:annotation:"

      def revision
        "vv-decision/v0.1.0/DecisionExtractor"
      end

      def applies_to?(episode)
        episode.kind == "decision_outcome"
      end

      def extract(episode, context:)
        decision = Vv::Decision::Decision.find_by(
          decision_outcome_episode_id: episode.id,
        )
        return [] unless decision&.decided?

        proposals = []
        subject   = "urn:vv-decision:decision:#{decision.id}"

        # Headline triple
        proposals << triple(s: subject, p: "rdf:type", o: "<#{VVDEC}Decision>")

        # Scalar content
        proposals << triple(s: subject, p: "#{VVDEC}context",        o: %("#{decision.context}"))
        proposals << triple(s: subject, p: "#{VVDEC}decided_option", o: %("#{decision.decided_option}"))
        proposals << triple(s: subject, p: "#{VVDEC}because",        o: %("#{decision.because}"))
        proposals << triple(s: subject, p: "#{VVDEC}decided_at",
                            o: %("#{decision.decided_at.iso8601}"^^xsd:dateTime))

        # Grounding evidence — one triple per IRI across all alternatives
        decision.alternatives.flat_map { |alt| alt["grounded_in_iris"] || [] }.uniq.each do |iri|
          proposals << triple(s: subject, p: "#{VVDEC}grounded_in", o: "<#{iri}>")
        end

        # Rejected alternatives
        decision.alternatives.reject { |alt| alt["option"] == decision.decided_option }.each do |alt|
          proposals << triple(s: subject, p: "#{VVDEC}alternative_to", o: %("#{alt["option"]}"))
        end

        # Reasoning trace (model only — prompt/completion stay in Bronze)
        if (model = decision.reasoning_payload["model"])
          proposals << triple(s: subject, p: "#{VVDEC}reasoned_with", o: %("#{model}"))
        end

        proposals
      end

      private

      def triple(s:, p:, o:)
        Vv::Memory::Conformer::TripleProposal.build(
          s: s, p: p, o: o, confidence: 1.0,
        )
      end
    end
  end
end
```

Registration (**as shipped — supersedes the sketch above**):
`Vv::Decision::Engine`'s `after_initialize` calls
`Vv::Decision.register_extractor!`, which invokes
`Vv::Memory::Conformer::StrategySelector.register(kind:
"decision_outcome", extractor_class:
Vv::Decision::DecisionExtractor)` — the registry surface vv-memory
shipped in v0.2.2 (CR_DS B1 option A). Registration is idempotent
(same-class re-registration is a no-op), so `register_extractor!`
is also safe to call directly from a non-Rails spec harness.

vv-memory's registry keys by episode **kind**, not by extractor
class, and ships **no** `unregister`. Operators who do not want
decision triples in their Silver thread a custom
`StrategySelector` subclass that doesn't route `decision_outcome`
and pass it through `conform!(strategy:)` (CR_DS B1 option B) —
rather than unregistering. The `extract` method shown above also
guards (`return [] unless decision&.decided?`), so a stray
`decision_outcome` episode without a decided `Decision` row emits
nothing.

#### Exit criteria
- Spec: a `deliberate(...) { |ctx| ctx.decide!(...) }` round-trip followed by `scope.conform_now!` emits the headline `rdf:type vvdec:Decision` triple into `scope.memory_silver[:iri]`.
- Spec: all six scalar content predicates (`context`, `decided_option`, `because`, `decided_at`, `reasoned_with`, plus `grounded_in` per evidence IRI) land as expected literals.
- Spec: rejected alternatives emit `vvdec:alternative_to` triples; the chosen option does NOT appear as its own `alternative_to`.
- Spec: an abandoned `deliberate` (no `decide!`) yields a `Decision` row with `decided_at: nil`; the extractor returns `[]` for the associated outcome episode (there is no outcome episode in that case — the spec confirms the extractor never fires).
- Spec: re-running `conform_now!` after a successful extraction is idempotent — the same triples land, no duplicates, no orphans (inherits vv-memory's per-(scope, extractor_revision) cursor).
- Spec: the parent Conformer's `vvmem:fromEpisode` / `vvmem:extractedBy` annotations land on the quoted-triple subject `<< <urn:vv-decision:decision:N> rdf:type <urn:vv-decision:annotation:Decision> >>`.

### Phase E — read-side aggregate methods

The four traversal methods named in DecisionLayer.md's "Minimum
viable surface" answer. Each composes a single SPARQL query
against the scope's Silver graph + an AR join against
`vv_memory_episodes`. No new tables, no caching layer.

```ruby
decision = Vv::Decision::Decision.find(42)

decision.trace_back               # decisions whose actions caused this decision's context
decision.alternatives_considered  # the rejected options + their grounded_in evidence
decision.impact                   # downstream episodes the action produced
decision.evidence_slice           # the recall result the decision was grounded in
```

#### Implementation

- `Decision#trace_back` — returns an `Array<Vv::Decision::Decision>`
  of prior decisions in the **same scope** whose
  `decision_outcome_episode.occurred_at` falls strictly before
  this decision's `decision_context_episode.occurred_at`. v0.1.0
  is timeline-shaped, not causal: "decisions that happened
  before this one" rather than "decisions that caused this one."
  The causal (`vvdec:caused_by` chain) traversal lands in v0.2.0
  once action emission ships and Bronze episodes carry causal
  back-references.
- `Decision#alternatives_considered` — returns an
  `Array<Hash>` mirroring the `alternatives` JSONB column,
  enriched: each hash gets an `evidence:` key whose value is a
  `Vv::Decision::EvidenceSlice` reconstructed by re-querying
  Silver for the stored `grounded_in_iris`.
- `Decision#impact` — returns the `Vv::Memory::Episode` rows in
  the same scope whose `occurred_at > decision.decided_at`. v0.1.0
  uses the timeline-correlation heuristic (every downstream
  episode in the scope is treated as potential impact); the
  precise impact-attribution model (correlating to the
  decision's action via a `caused_by` chain) lands in v0.2.0.
  Returns the AR relation, not an array, so operators can
  paginate.
- `Decision#evidence_slice` — returns a `Vv::Decision::EvidenceSlice`
  reconstructed from the union of `grounded_in_iris` across all
  alternatives. Re-queries Silver to hydrate the latest values;
  if a grounding IRI no longer exists in Silver (the operator
  retracted it), the slice silently omits it. The original IRIs
  remain in the JSONB column for audit.
- `Decision#reasoning_trace` — returns the stored
  `reasoning_payload` Hash with string keys symbolized. Trivial
  reader, listed here for surface completeness.

The four methods are intentionally instance-level; the class-level
`Vv::Decision.find_precedents(context:, scope:, k:)`,
`.analyze_impact_pattern(scope:, option:)`, and
`.check_policies(scope:)` surfaces from DecisionLayer.md's
Open question 3 are **deferred to v0.2.0**.

#### Exit criteria
- Spec: `decision.trace_back` returns only decisions in the same scope whose outcome episode predates this decision's context episode; cross-scope decisions are excluded.
- Spec: `decision.alternatives_considered` returns the rejected options (excluding `decided_option`); each entry's `evidence:` is an `EvidenceSlice` whose iris match the stored `grounded_in_iris`.
- Spec: `decision.impact` returns Bronze episodes in the same scope with `occurred_at > decided_at`; returns an `ActiveRecord::Relation` (paginable).
- Spec: `decision.evidence_slice` returns an `EvidenceSlice` whose row count equals the live-Silver count for the stored grounding IRIs; retracted IRIs omit silently.
- Spec: `decision.reasoning_trace` round-trips the `reasoning_payload` Hash.

### Phase F — Integration spec, `bin/check`, docs

- `spec/vv/decision/deliberate_integration_spec.rb` — the v0.1.0
  acceptance signal in one test. Full happy path:
  1. `FakeSession.create!` (includes `Vv::Memory::Scoped`).
  2. Seed Silver with a few `mm:order:*` triples for `recall` to find.
  3. `Vv::Decision.deliberate(scope: session, context: "x") do |ctx|` — call all four flow methods; `decide!` at the end.
  4. Assert the returned `Decision` is persisted + decided.
  5. Assert the five-kind Bronze flow landed
     (`decision_context` + `decision_query` + N × `decision_consider` + `decision_reasoning` + `decision_outcome`).
  6. `session.conform_now!`.
  7. Assert the `vvdec:Decision` headline + content triples land in `session.memory_silver[:iri]`.
  8. Assert the parent Conformer's `vvmem:` annotations land on the quoted-triple subject.
  9. Assert all four read-side methods (`trace_back`, `alternatives_considered`, `impact`, `evidence_slice`) return the expected shapes.
  10. `session.memory_silver[:checkpoint!].call`; `Vv::Graph::EtherealGraph.evict!(silver_iri)`; `session.memory_silver[:hydrate!].call`; re-assert all `vvdec:` triples survived (proves the Silver story round-trips through Active Storage).

- `bin/check` — single operator-runnable script:
  1. `bundle install` (idempotent).
  2. Verify the `sqlite-sparql` artifact via `vendor/vv-graph/bin/check`'s engine-detection logic, or emit an explicit error pointing at vv-graph's PLAN_0.1.0.
  3. Verify `vv-memory ≥ 0.2.0` is in the bundle (the
     `Vv::Memory::Conformer::Extractor` constant check).
  4. `bundle exec rspec`.
  5. Exit non-zero on any failure with a verbatim error tail.

- Docs (Phase F deliverables):
  - `CHANGELOG.md` — `0.1.0` heading with per-phase entries.
  - `README.md` — expand existing placeholder into a Quickstart section with the `deliberate(...)` example (the README's "Sketch of the surface" already has the shape; Phase F tightens it to the actually-shipped surface and removes any sketch-only language).
  - `CONSUMER_REQUIREMENT_MM.md` — note that `mm-server` is the first intended consumer; lists which scopes should use `deliberate(...)` (`Session`, `Workspace`) and the `kind:`-string conventions operators should NOT collide with (`decision_context`, `decision_query`, `decision_consider`, `decision_reasoning`, `decision_outcome`).
  - `docs/plans/PLAN_0_1_0.md` — this file. Update "Current state baseline" as phases land.
  - `VERSION` → `0.1.0`.

#### Exit criteria
- `bin/check` exits 0 against the canonical dev environment (vv-graph ≥ 0.13.0 with built engine, vv-memory ≥ 0.2.0).
- The integration spec passes — load-bearing test for the v0.1.0 contract.
- `CHANGELOG.md` `0.1.0` heading drops `(unreleased)`.

## Out of scope for v0.1.0

- **Class-level analytical facades.** `Vv::Decision.find_precedents(context:, scope:, k:)`, `.analyze_impact_pattern(scope:, option:)`, `.check_policies(scope:)`. Sketched in DecisionLayer.md; deferred to v0.2.0.
- **Causal (`vvdec:caused_by`) traversal.** v0.1.0's `#trace_back` and `#impact` use timeline correlation in the same scope. Causal chains require action-emission + completion-callback machinery; lands in v0.2.0.
- **Action emission + completion callback.** `ctx.act!(tool:, args:)` and the corresponding `decision_action` / `decision_action_completed` episodes. v0.1.0's `decide!` records intent only. Open question 6 from DecisionLayer.md — likely resolves via the existing RES pattern in `mm-server`.
- **Curator integration (Gold tier).** Promoting "in this context the agent consistently chose X" patterns into curated commitments. Depends on `vv-memory` PLAN_0.3.0 (Curator) shipping. Open question 7 — out of v0.1.0 scope; tracked.
- **`Vv::Memory.recall(...)` facade integration.** v0.1.0 ships the thin Silver-only recall (`ctx.recall(query: sparql_string)`); `depth: :gold` / `:bronze` raise `Errors::RecallDepthUnsupported`. Once `vv-memory` PLAN_0.4.0 ships, this gem's `ctx.recall` delegates and the refusal lifts.
- **LLM invocation inside `deliberate(...)`.** `ctx.reason_with(model:, prompt:, completion:)` records a trace; the operator supplies the completion. v0.1.0 does not invoke any model. The gem is layering-neutral on the model choice — `model:` is a freeform string. v0.2.0+ may add a `model_adapter:` hook.
- **Multi-scope decision queries.** "Find every Decision for this User across all their Sessions." Possible today by union-querying named graphs; not packaged as a facade method in 0.1.0.
- **Decision-pattern shaping** (SHACL-style validation of well-formed decisions). Could live in Silver via a `Vv::Graph::Shacl` shape declaration; the gem does not ship one in v0.1.0.
- **Publishing to rubygems.org.** Path-sourced under `vendor/vv-decision/` for the entire v0.x.x line.

## v0.1.0 contract additions (frozen at release)

| Surface | Shape | Mutability |
|---|---|---|
| `Vv::Decision.deliberate(scope:, context:, provenance_id: nil, &block)` → `Vv::Decision::Decision` | module method | **Pinned.** |
| `Vv::Decision::DeliberationContext#recall(query:, depth: :silver)` | instance method | **Pinned.** `depth:` accepts `:silver` only in 0.1.0; `:gold` / `:bronze` raise `RecallDepthUnsupported` (refusal symbol pinned — additive when lifted). |
| `Vv::Decision::DeliberationContext#consider(option:, grounded_in:, rejected_because: nil)` | instance method | **Pinned.** |
| `Vv::Decision::DeliberationContext#reason_with(model:, prompt:, completion: nil)` | instance method | **Pinned.** |
| `Vv::Decision::DeliberationContext#decide!(option:, because:)` | instance method | **Pinned.** Calling twice raises `AlreadyDecided`. |
| `Vv::Decision::Decision` AR model + `vv_decision_decisions` table | schema | **Pinned column names.** Additive new columns allowed in 0.1.x. |
| `Vv::Decision::Decision#decided?` / `#option` / `#trace_back` / `#alternatives_considered` / `#impact` / `#evidence_slice` / `#reasoning_trace` | instance methods | **Pinned.** Semantics of `trace_back` / `impact` are timeline-correlation in 0.1.0; tighten to causal in v0.2.0 (semantically additive — old callers see a strict subset of the prior result, not a different one). |
| `Vv::Decision::EvidenceSlice#where` / `#iris` / `#count` / `#to_a` | value object | **Pinned.** |
| `Vv::Decision::DecisionExtractor` (registered with vv-memory Conformer) | extractor class | **Pinned `revision:` string** (`"vv-decision/v0.1.0/DecisionExtractor"`). Triples it emits are pinned at the `vvdec:` predicate names listed in Phase D. |
| `vvdec:` namespace IRI prefix (`urn:vv-decision:annotation:`) | convention | **Pinned for the v0.x.x line.** |
| Bronze episode `kind:` strings (`decision_context`, `decision_query`, `decision_consider`, `decision_reasoning`, `decision_outcome`) | convention | **Pinned.** Operators must not use these `kind:` strings for unrelated purposes. |
| `Vv::Decision::Errors::MissingDependency` / `InvalidDeliberation` / `AlreadyDecided` / `RecallDepthUnsupported` / `NoDecisionMade` | exception classes | **Pinned class names** (the `NoDecisionMade` class is defined but not raised by v0.1.0's `deliberate` — operators may use it themselves when their code expects a decision but `decision.decided? == false`). |

No structured-envelope `{ ok:, reason:, because: }` surface in
v0.1.0 — the gem composes Active Record exceptions for persistence,
`Vv::Graph::Sparql` envelopes for SPARQL, and Ruby exceptions for
its own contract violations. The unified envelope surface waits
until the analytical facades land in v0.2.0+.

## Risks

| Risk | Mitigation |
|---|---|
| `vv-memory` 0.2.0's Conformer Extractor interface has not stabilized — its `Extractor` base class is a v0.2.0 deliverable that may still shift. | Phase A's `MissingDependency` guard checks for both `Vv::Memory::Scoped` and `Vv::Memory::Conformer::Extractor` constants. If the Extractor surface shifts late in vv-memory 0.2.x, Phase D's spec catches the breakage. Pin `vv-memory >= 0.2.0` in the gemspec; tighten to `>= 0.2.x` once the Extractor surface is frozen. |
| Decision-flow Bronze episodes pollute the scope's general episode stream; consumers that paginate `scope.memory_episodes` see a lot of `decision_*` rows interleaved with their domain rows. | Document. The `kind:` string convention is a feature, not a bug — operators can scope queries with `scope.memory_episodes.where.not(kind: Vv::Decision::EPISODE_KINDS)`. Constant exposed from `Vv::Decision` for that purpose. |
| Operators forget that `deliberate(...)` only writes Bronze + the Decision aggregate; Silver triples don't appear until `conform_now!`. | README's Quickstart explicitly calls out the two-phase nature. The integration spec (Phase F) round-trips both, making the expectation testable. The decision NOT to auto-trigger the Conformer inside `deliberate(...)` is documented (forward-acting vs. backward-acting concerns must not couple). |
| The thin `recall(query: sparql_string)` v0.1.0 surface forces operators to write SPARQL by hand — fine for the substrate, painful for downstream consumers. | Intentional. v0.1.0 is for the substrate; the DSL-shaped `query: "..."` → SPARQL translation is a v0.2.0 deliverable (likely as a `Vv::Decision::QueryDsl` value object or via `Vv::Memory.recall(...)` once it ships). The thin surface lets the substrate ship without waiting on the DSL design. |
| `Decision#trace_back` / `#impact` use timeline correlation in v0.1.0; operators may build dashboards on top expecting causal semantics. | Documented as timeline-correlation in the README + the v0.1.0 contract table. The v0.2.0 tightening to causal semantics is semantically additive (strict subset). Dashboard owners get a stricter result set, not a different one. |
| The `vvdec:` predicate names collide with another consumer's vocabulary. | The prefix `urn:vv-decision:annotation:` is namespaced. Operators with conflicting predicates re-namespace their own; this gem's predicate IRIs are pinned at v0.1.0. |
| Transaction wrapping in `deliberate(...)` means a slow LLM call inside `ctx.reason_with(...)` holds the DB transaction open. | v0.1.0 does NOT invoke the LLM — the operator supplies `completion:` after the call returns. The transaction wraps only the bookkeeping. If a later version adds inline LLM invocation, the transaction shape must change (likely a two-transaction pattern: open → call → reopen → commit). Tracked as a v0.2.0 design constraint. |
| Polymorphic `scope` association on `Vv::Decision::Decision` makes cross-table queries awkward (same risk vv-memory PLAN_0.1.0 accepted). | Same mitigation: acceptable for v0.1.0 — known polymorphic-AR limitation; consumers iterate per-scope-type. |
| Operator unregisters `DecisionExtractor` from the Conformer and then runs `conform_now!`; the Silver tier silently lacks decision triples. | Document the registration + unregistration pattern in the README. The integration spec asserts registration happens at Engine boot. Operators who unregister own the consequence; the gem does not police runtime extractor membership. |

## Acceptance signal

1. Phases A/B/C/D/E/F land with passing specs; Phase F's integration spec is green.
2. `bin/check` green against the canonical dev environment.
3. `CHANGELOG.md` `0.1.0` heading drops `(unreleased)`.
4. `VERSION` → `0.1.0`.
5. `README.md` documents the `deliberate(...)` entrypoint, the two-phase (Bronze immediate, Silver via Conformer) write story, and the four read-side methods.
6. `CONSUMER_REQUIREMENT_MM.md` notes the first `mm-server` consumer surface + the reserved `kind:` strings.
7. The substrate `Gemfile` adds `vv-decision` via path source; at least one scope (`Session`) carries a real `deliberate(...)` call in a `mm-server` agent path against the tagged 0.1.0. (Tracked as the 0.1.1 / first-consumer-PR milestone if not landed concurrently with the tag.)

## Cross-references

- `../../../../docs/research/DecisionLayer.md` — the architectural finding; open questions tracked there until subsequent PLANs land here.
- `../../../vv-memory/docs/plans/PLAN_0.1.0.md` — Bronze + Silver substrate.
- `../../../vv-memory/docs/plans/PLAN_0.2.0.md` — Conformer + Extractor interface (this gem's primary integration point).
- `../../../vv-memory/docs/plans/PLAN_0.4.0.md` — `Vv::Memory.recall(...)` facade (the v0.1.0 thin recall stands in for this until it ships).
- `../../../vv-graph/docs/plans/PLAN_0.13.0.md` — `Vv::Graph::Scope` value object.
- `../../../vv-graph/CONSUMER_REQUIREMENT_VV.md` — boundary item B4 (the layering-correction ask back to PLAN_0.14.0).
- `../../README.md` — this gem's README (Quickstart + three-layer sidebar).
- [`semantica-agi/semantica`](https://github.com/semantica-agi/semantica) — upstream Python project whose decision-intelligence DSL motivated PLAN_0.14.0 and whose decision-as-data framing this gem pushes back against.
