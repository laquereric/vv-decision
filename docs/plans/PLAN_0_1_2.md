# PLAN_0_1_2 — `vv-decision` implementation plan

> *Turns the **design** plans of v0.1.0 and v0.1.1 into shipped
> code. The previous two PLANs are forward-looking specifications;
> this one is the **execution sequence** — what's already built,
> what's left, in what order, gated on what sibling-gem
> verifications, with what checkpoints. v0.1.2 the tag is the
> **first-consumer-PR milestone** that both prior plans pre-committed
> to (PLAN_0_1_0 §Acceptance signal item 7; PLAN_0_1_1 §Acceptance
> signal item 8): the substrate's `mm-server` Gemfile carries
> `vv-decision` via path source, and at least one agent path
> exercises `deliberate(..., epistemic_schema:)` against tagged
> 0.1.1. The bet of this plan: implement strictly to the frozen
> design surfaces — no contract drift, no scope creep; when the
> implementation discovers a design-time assumption is wrong, stop
> and amend the design PLAN rather than papering over it in code.*

## Anchors

| Anchor | Where | Role |
|---|---|---|
| `./PLAN_0_1_0.md` | this directory | The v0.1.0 design plan. Phases A–F + frozen contract table. Phase A is implemented; B–F are this plan's work units 1–5. |
| `./PLAN_0_1_1.md` | this directory | The v0.1.1 design plan. Epistemic schemas, additive on v0.1.0. Phases A–E are this plan's work units 6–10. |
| `../research/DecisionLayer.md` (parent repo) | `../../../../docs/research/DecisionLayer.md` | The architectural finding behind the gem. Re-anchor here if a phase's implementation discovers a deeper-than-design issue. |
| `../research/DecisionContext.md` (parent repo) | `../../../../docs/research/DecisionContext.md` | The 2KB-file finding that motivates v0.1.1. Re-anchor here if the tripwire surface needs amendment. |
| `vendor/vv-memory/lib/vv/memory/conformer/extractor.rb` | sibling | The `Vv::Memory::Conformer::Extractor` base class — Phase D / work unit 4's integration point. Verified surface gate G2 (below) reads this file before any extractor work begins. |
| `vendor/vv-memory/lib/vv/memory/scoped.rb` | sibling | The `Vv::Memory::Scoped` concern — the polymorphic scope contract every `deliberate(...)` call requires. Verified surface gate G1 reads this before Phase B/C work begins. |
| `vendor/vv-graph/lib/vv/graph/sparql.rb` (or equivalent) | sibling | The `Vv::Graph::Sparql.select(query, graph:)` surface — Phase C / work unit 3's recall integration point. Verified surface gate G3 reads this before recall work begins. |

## Current state baseline (2026-05-26)

**Built (PLAN_0_1_0 Phase A, committed `3117481` → `d6bc260`):**

- `vv-decision.gemspec` — runtime deps pinned: `vv-memory >= 0.2.0`, `vv-graph ~> 0.15`, `activerecord/activesupport/railties >= 8.0`. Dev deps: `rspec ~> 3.13`, `rake ~> 13.0`, `sqlite3 ~> 2.4`.
- `Gemfile` — path-vendored `vv-memory` and `vv-graph` at `../vv-memory` / `../vv-graph`.
- `lib/vv/decision.rb` — top-level entry; requires `version`, `errors`, eager-requires `vv/memory`, loads `engine` when Rails is present.
- `lib/vv/decision/engine.rb` — `Rails::Engine` with `isolate_namespace Vv::Decision`, `eager_load_namespaces`, and the `after_initialize` `MissingDependency` guard (checks both `Vv::Memory::Scoped` and `Vv::Memory::Conformer::Extractor` constants).
- `lib/vv/decision/errors.rb` — all five v0.1.0 error classes (`MissingDependency`, `InvalidDeliberation`, `AlreadyDecided`, `RecallDepthUnsupported`, `NoDecisionMade`).
- `lib/vv/decision/version.rb` — `VERSION = "0.1.0"`.
- `spec/spec_helper.rb` + support files (`extension_environment.rb`, `active_storage_environment.rb`, `schema.rb`) — harness already anticipates Phase B/C/D/E/F:
  - `Schema.ensure!` pre-creates `vv_memory_episodes`, `vv_memory_conformer_cursors`, `vv_memory_conformer_quality`, and `sessions` (the Phase C/F fixture scope).
  - The extension environment loads the compiled `sqlite-sparql` and skips `:requires_extension` specs cleanly when absent.
- Spec files exist for the built surface: `version_spec.rb`, `errors_spec.rb`, `engine_spec.rb`.
- Docs: `README.md`, `CHANGELOG.md` (`0.1.0 — (unreleased)`), `LICENSE`, `VERSION` (`0.1.0`).
- `bin/check` is present (Phase A skeleton).

**Not built (the work this plan executes):**

- v0.1.0 Phases B–F (work units 1–5).
- v0.1.1 Phases A–E (work units 6–10).
- v0.1.2 first-consumer-PR integration in `mm-server` (work unit 11).

## Pre-flight verification gates

Before any implementation work begins, three sibling-gem surfaces
must be re-read and the design plans amended if the implementation
assumption is wrong. **Stop and ask the user before amending a
design plan.** These gates exist because the design plans were
written against the *anticipated* sibling surface; verifying
against the *actual* surface protects us from spending a phase
building on bad assumptions.

| Gate | What to verify | Pass criterion | Failure response |
|---|---|---|---|
| **G1 — `Vv::Memory::Scoped` surface** | Read `vendor/vv-memory/lib/vv/memory/scoped.rb`. Confirm the concern exposes (a) `record_episode(kind:, payload:, occurred_at: nil)` returning an `Episode` row, (b) a polymorphic `scope_type/scope_id` column shape on `vv_memory_episodes`, (c) the `memory_silver[:iri]` accessor that the design plans call. | All three present with the documented signatures. | Stop. Identify the actual signature. Ask the user whether to (i) amend PLAN_0_1_0 to match, or (ii) ask the vv-memory maintainer to align. |
| **G2 — `Vv::Memory::Conformer::Extractor` revision convention** | Read `vendor/vv-memory/lib/vv/memory/conformer/extractor.rb`. PLAN_0_1_0 §Phase D pins the extractor revision as `"vv-decision/v0.1.0/DecisionExtractor"`. vv-memory's actual convention (per its own comments) is `<class-shortname>-v<integer>`. | Either the vv-memory base class accepts the design-plan format, OR the design plan is amended to match the convention (e.g., `"decision-v1"` / `"decision-v2"`). | Stop. Ask the user whether to amend PLAN_0_1_0 §Phase D + the contract table to use `"decision-v1"` (and PLAN_0_1_1 §Phase D to use `"decision-v2"`), or to leave the design plan as-is and document the deviation in the extractor's `#revision` implementation. **This is a known mismatch** — flag it explicitly to the user before work unit 4 begins. |
| **G3 — `Vv::Graph::Sparql.select` signature** | Confirm `Vv::Graph::Sparql.select(query_string, graph: iri)` returns a Hash with a `:results` array of row hashes, as PLAN_0_1_0 §Phase C uses. | Signature + return shape match. | Stop. Identify the actual signature. Ask whether to amend PLAN_0_1_0 or use an adapter. |

Gates G1 + G2 + G3 are blocking for work units 1–4. Gate G3 alone
gates work unit 3. **The implementer is expected to run these
gates as the first action of work unit 1; the gates take ~5
minutes each.**

## Sequencing principles

1. **Strict implementation order.** Each work unit's exit criteria are the design plan's exit criteria. The implementer does not invent new exit criteria; if the design's exit criteria are unreachable, stop and amend the design.
2. **Spec-first within a phase.** The design plans state exit criteria as RSpec scenarios. Write the spec first (red), implement to green, refactor with the suite green. The harness in `spec/` is already configured for this loop.
3. **No design drift.** If the implementation discovers a missing surface that the design didn't anticipate (e.g., a helper class, a constant, an additional error case), the implementer pauses and the design plan is updated *before* the code lands. Code merged ahead of the design is the failure mode this plan exists to prevent.
4. **Tag at exit criteria, not at convenience.** v0.1.0 is tagged the moment work unit 5 (Phase F integration spec) is green. v0.1.1 is tagged the moment work unit 10 (Phase E integration spec) is green. Work unit 11 — the first-consumer-PR — closes v0.1.2 and is itself the v0.1.2 acceptance signal.
5. **Each work unit ends with a commit.** Small commits over big ones. The CHANGELOG entry is part of the work unit, not deferred to Phase F / Phase E.
6. **Sibling-gem dependence is read-only.** vv-decision never edits files in `vendor/vv-memory/` or `vendor/vv-graph/`. If a sibling-gem surface gap is discovered, the implementer stops and asks the user before any cross-repo edit.

## Work units

Each work unit has: **goal**, **inputs**, **the spec to write first**, **the implementation deliverable**, **exit criteria** (copied verbatim from the design plan), and **commit message shape**.

### Work unit 1 — v0.1.0 Phase B: `Vv::Decision::Decision` AR model

**Goal:** Persist the aggregate root. One AR row per `deliberate(...)` call.

**Gate:** G1 must pass.

**Inputs:** PLAN_0_1_0 §Phase B (lines ~192–268).

**Spec first:** `spec/vv/decision/decision_spec.rb` — five scenarios from the Phase B exit criteria.

**Deliverable:**
- `db/migrate/20260525000001_create_vv_decision_decisions.rb` — exact schema from PLAN_0_1_0 §Phase B.
- `app/models/vv/decision/decision.rb` — AR model with polymorphic `scope`, FK belongs_to associations to `Vv::Memory::Episode`, the three named scopes (`decided` / `since` / `for_option`), `#decided?`, `#option`.
- Wire the migration into `spec/support/schema.rb` so the in-memory SQLite suite carries the table.
- Add `require "vv/decision/decision"` to `lib/vv/decision.rb` (guarded by `if defined?(::ActiveRecord::Base)`).

**Exit criteria** (verbatim from PLAN_0_1_0 §Phase B):
- Spec: creating a `Decision` with `scope:`, `context:` persists; reload round-trips the JSONB columns.
- Spec: `provenance_id` uniqueness enforced.
- Spec: polymorphic `scope` association resolves back to the AR record.
- Spec: `decided`, `since`, `for_option` scopes return the expected subsets.
- Spec: `Decision#decided?` returns `false` until `decided_at` is set.

**Commit:** `PLAN_0_1_0 Phase B: Vv::Decision::Decision AR aggregate root`.

### Work unit 2 — v0.1.0 Phase C: `deliberate(...)` + `DeliberationContext`

**Goal:** The consumer-facing entrypoint and the four flow methods (`recall` / `consider` / `reason_with` / `decide!`).

**Gate:** G1 + G3 must pass.

**Inputs:** PLAN_0_1_0 §Phase C (lines ~270–376).

**Spec first:** `spec/vv/decision/deliberation_context_spec.rb` — nine scenarios from the Phase C exit criteria. Use a `FakeSession` fixture (the `sessions` table is already in `spec/support/schema.rb`) including `Vv::Memory::Scoped`.

**Deliverable:**
- `lib/vv/decision/deliberation_context.rb` — `#recall`, `#consider`, `#reason_with`, `#decide!`.
- `lib/vv/decision/evidence_slice.rb` — read-only value object with `#where(predicate:, subject:, object:)`, `#iris`, `#count`, `#to_a`.
- Extend `lib/vv/decision.rb` with `def self.deliberate(scope:, context:, provenance_id: nil, &block)` — transaction wrap, Bronze `decision_context` episode, build the `Decision` row, yield `DeliberationContext`, finalize on block exit.
- Add the reserved-kinds constant: `Vv::Decision::EPISODE_KINDS = %w[decision_context decision_query decision_consider decision_reasoning decision_outcome].freeze`. (PLAN_0_1_1 will extend this with `decision_tripwire` in work unit 9.)

**Exit criteria** (verbatim from PLAN_0_1_0 §Phase C):
- Spec: `deliberate(scope: …, context: "x") { |ctx| ctx.decide!(option: :a, because: "y") }` returns a persisted `Decision` with `decided_at != nil`, `decided_option == "a"`, `because == "y"`, paired episodes.
- Spec: block raises → full state rolls back.
- Spec: block exits without `decide!` → persisted `Decision` with `decided_at: nil`, `decision.decided? == false`.
- Spec: double `decide!` raises `AlreadyDecided`.
- Spec: `ctx.recall` returns an `EvidenceSlice` whose row count matches `Vv::Graph::Sparql.select(...)[:results].size`; records a `decision_query` episode.
- Spec: `ctx.recall(depth: :gold)` raises `RecallDepthUnsupported`.
- Spec: `ctx.consider` appends + records a `decision_consider` episode.
- Spec: `ctx.reason_with` sets `reasoning_payload` + records a `decision_reasoning` episode.
- Spec: `provenance_id` uniqueness at outer-transaction commit.

**Commit:** `PLAN_0_1_0 Phase C: deliberate(...) + DeliberationContext + EvidenceSlice`.

### Work unit 3 — v0.1.0 Phase D: `DecisionExtractor` (Conformer subclass)

**Goal:** Bronze → Silver promotion via the Conformer interface; emits the `vvdec:` predicates listed in PLAN_0_1_0 §Phase D.

**Gate:** G2 must pass — and the result may amend the design plan (see G2 §Failure response). If the design plan is amended to use the `<class-shortname>-v<integer>` convention, the new revision string is `"decision-v1"`; v0.1.1 (work unit 9) bumps to `"decision-v2"`.

**Inputs:** PLAN_0_1_0 §Phase D (lines ~377–502).

**Spec first:** `spec/vv/decision/decision_extractor_spec.rb` — six scenarios from the Phase D exit criteria. These specs require the `sqlite-sparql` extension; tag them `:requires_extension` so they skip cleanly without it.

**Deliverable:**
- `lib/vv/decision/decision_extractor.rb` — subclass of `Vv::Memory::Conformer::Extractor`; implements `#applies_to?`, `#extract(episode, context:)`, `#revision`.
- Register the extractor in `Engine` (or a Railtie initializer): `config.after_initialize do; Vv::Memory::Conformer::ExtractorRegistry.register(Vv::Decision::DecisionExtractor); end`. Verify the registry's class name and method name during gate G2.
- A `Vv::Decision::Vocabulary` module exposing `VVDEC = "urn:vv-decision:annotation:"` so v0.1.1 work units can reuse it without duplicating the constant.

**Exit criteria** (verbatim from PLAN_0_1_0 §Phase D):
- Spec: round-trip emits `rdf:type vvdec:Decision` triple.
- Spec: all six scalar content predicates land.
- Spec: rejected alternatives emit `vvdec:alternative_to`; chosen option excluded.
- Spec: abandoned `deliberate` → extractor returns `[]`.
- Spec: idempotent re-run via cursor.
- Spec: parent Conformer `vvmem:fromEpisode` + `vvmem:extractedBy` annotations land on the quoted-triple subject.

**Commit:** `PLAN_0_1_0 Phase D: DecisionExtractor + vvdec: vocabulary`.

### Work unit 4 — v0.1.0 Phase E: read-side traversal methods

**Goal:** The four (+ one trivial) read-side methods on `Decision`.

**Gate:** G3 (still in effect).

**Inputs:** PLAN_0_1_0 §Phase E (lines ~503–565).

**Spec first:** `spec/vv/decision/traversal_spec.rb` — five scenarios from the Phase E exit criteria.

**Deliverable:**
- Add `#trace_back`, `#alternatives_considered`, `#impact`, `#evidence_slice`, `#reasoning_trace` to `app/models/vv/decision/decision.rb`.
- `#trace_back` is timeline-correlated in v0.1.0 (not causal); document this in the method's docstring.
- `#impact` returns `ActiveRecord::Relation`, not `Array`.

**Exit criteria** (verbatim from PLAN_0_1_0 §Phase E):
- Spec: `decision.trace_back` returns same-scope decisions only.
- Spec: `decision.alternatives_considered` excludes the decided option; each entry's evidence iris match.
- Spec: `decision.impact` is an AR relation, scope-filtered, time-filtered.
- Spec: `decision.evidence_slice` row count equals live-Silver count; retracted IRIs omit silently.
- Spec: `decision.reasoning_trace` round-trips the payload Hash.

**Commit:** `PLAN_0_1_0 Phase E: Decision read-side traversal methods`.

### Work unit 5 — v0.1.0 Phase F: integration spec, `bin/check`, docs → **tag 0.1.0**

**Goal:** v0.1.0 acceptance signal. The integration spec round-trips the full happy path; docs are tightened to the actually-shipped surface; `CHANGELOG.md` drops `(unreleased)`.

**Inputs:** PLAN_0_1_0 §Phase F (lines ~566–600).

**Spec first:** `spec/vv/decision/deliberate_integration_spec.rb` — the 10-step round-trip listed in PLAN_0_1_0 §Phase F. Tagged `:requires_extension`.

**Deliverable:**
- Integration spec green.
- `bin/check` performs the five-step script from PLAN_0_1_0 §Phase F (bundle, sqlite-sparql verify, vv-memory verify, rspec, exit code).
- `CHANGELOG.md` — fill in the `0.1.0` section with per-phase entries summarizing work units 1–5; drop `(unreleased)`.
- `README.md` — expand the "Sketch of the surface" into a true Quickstart documenting the actually-shipped surface.
- `CONSUMER_REQUIREMENT_MM.md` — new file; lists the reserved `kind:` strings and the recommended scope types for the consumer.
- `VERSION` stays `0.1.0`.

**Acceptance:** PLAN_0_1_0 §Acceptance signal items 1–6 are met. Item 7 (the first-consumer-PR in mm-server) is tracked here under work unit 11 — not a blocker for the v0.1.0 tag.

**Tag:** `v0.1.0` annotated tag. Push the tag.

**Commit:** `PLAN_0_1_0 Phase F: integration spec + bin/check + docs; tag v0.1.0`.

### Work unit 6 — v0.1.1 Phase A: `EpistemicSchema` value object

**Goal:** The immutable value object with three constructors, validation, and the content-IRI helper.

**Gate:** None. Pure-Ruby value object; no sibling-gem surface required.

**Inputs:** PLAN_0_1_1 §Phase A.

**Spec first:** `spec/vv/decision/epistemic_schema_spec.rb` — five scenarios from the Phase A exit criteria, plus a spec for `#content_iri` round-trip (same canonical-JSON → same IRI).

**Deliverable:**
- `lib/vv/decision/epistemic_schema.rb` — the value object.
- New error classes in `lib/vv/decision/errors.rb`: `InvalidEpistemicSchema`, `EpistemicSchemaTooLarge`, `TripwireFired` (the last for work unit 8 but added here as part of the errors surface bump).
- `#content_iri` uses `Digest::SHA256.hexdigest` over canonical JSON (sorted keys, no whitespace).

**Exit criteria** (verbatim from PLAN_0_1_1 §Phase A): five scenarios, plus the content-IRI round-trip.

**Commit:** `PLAN_0_1_1 Phase A: EpistemicSchema value object + error surface`.

### Work unit 7 — v0.1.1 Phase B: `deliberate(..., epistemic_schema:)` + persistence

**Goal:** The kwarg lands on `deliberate(...)`; two new jsonb columns persist the schema and tripwire log.

**Gate:** None new.

**Inputs:** PLAN_0_1_1 §Phase B.

**Spec first:** Five scenarios from the Phase B exit criteria, in `spec/vv/decision/deliberation_context_spec.rb` (extending the file from work unit 2).

**Deliverable:**
- `db/migrate/20260526000001_add_epistemic_schema_to_vv_decision_decisions.rb` — adds `epistemic_schema` (jsonb default `{}`) and `tripwires_fired` (jsonb default `[]`). The migration is additive; existing v0.1.0 rows backfill trivially.
- Update `spec/support/schema.rb` to include the new columns.
- `Vv::Decision.deliberate` signature adds `epistemic_schema: nil`. The kwarg defaults to `nil` so all v0.1.0 call sites resolve unchanged.
- `DeliberationContext#schema` reader.
- `Decision#epistemic_schema` (memoized; returns `nil` for empty jsonb) and `#tripwires_fired` (raw jsonb array).

**Exit criteria** (verbatim from PLAN_0_1_1 §Phase B): five scenarios.

**Backward-compat assertion:** The full v0.1.0 spec suite (work units 1–5) runs unchanged. Any v0.1.0 spec touched by this work unit is a contract-drift failure; stop and ask the user.

**Commit:** `PLAN_0_1_1 Phase B: epistemic_schema kwarg + persistence (additive)`.

### Work unit 8 — v0.1.1 Phase C: tripwire interpreter

**Goal:** The interpreter runs at the four flow stages, dispatches the three actions, raises `TripwireFired` for `refuse_and_flag`.

**Gate:** None new.

**Inputs:** PLAN_0_1_1 §Phase C.

**Spec first:** Seven scenarios from the Phase C exit criteria, plus a spec for each of the five built-in patterns (positive + negative case) — 17 specs total. File: `spec/vv/decision/tripwire_interpreter_spec.rb`.

**Deliverable:**
- `lib/vv/decision/tripwire_interpreter.rb` — stateless module with `.check_recall!`, `.check_reason_with!`, `.check_decide!`, `.check_consider!`.
- `lib/vv/decision/tripwire_patterns.rb` — the five built-in pattern matchers (`option_in_knowledge_gap` / `query_in_knowledge_gap` / `exact_citation_without_source` / `numeric_claim_no_audit` / `unverified_domain_claim`).
- `DeliberationContext` calls the appropriate `check_*` at each flow stage before the v0.1.0 work. Short-circuits when `schema` is `nil` (zero overhead for non-schema callers).
- Action dispatch logic in `DeliberationContext`: append Bronze `decision_tripwire` episode, append to `tripwires_fired`, raise `TripwireFired` if any matched entry's action is `refuse_and_flag`.
- Add `"decision_tripwire"` to `Vv::Decision::EPISODE_KINDS`.

**Exit criteria** (verbatim from PLAN_0_1_1 §Phase C): seven scenarios + the per-pattern specs.

**Commit:** `PLAN_0_1_1 Phase C: tripwire interpreter + 5 built-in patterns`.

### Work unit 9 — v0.1.1 Phase D: `DecisionExtractor` revision bump + new predicates

**Goal:** The extractor revision bumps; new `vvdec:` predicates emit when the schema column is non-empty. Existing decisions backfill via the per-`(scope, revision)` cursor replay in `vv-memory`.

**Gate:** G2 (still in effect — if the revision-convention amendment landed at gate G2, this work unit uses `"decision-v2"`; if the original `"vv-decision/v0.1.1/DecisionExtractor"` stayed, use that).

**Inputs:** PLAN_0_1_1 §Phase D.

**Spec first:** Five scenarios from the Phase D exit criteria, in `spec/vv/decision/decision_extractor_spec.rb` (extending work unit 3's file). Tagged `:requires_extension`.

**Deliverable:**
- Bump `DecisionExtractor#revision` to the new string.
- Extend `#extract(episode, context:)` to emit (a) `vvdec:bounded_by` when `epistemic_schema` non-empty, (b) `vvdec:verified_domain` per verified-domain key, (c) `vvdec:knowledge_gap` per gap entry, (d) one `vvdec:tripwire_fired` IRI + four scalar predicates per fired-tripwire entry.
- `EpistemicSchema#content_iri` already lives in work unit 6; this work unit uses it.
- The optional **shim**: `Vv::Decision::DecisionExtractor::V0_1_0` — a marker class operators can register if they want to pin the older revision and avoid the re-emit cost. Tracked as a v0.1.1 deliverable per PLAN_0_1_1 §Risks row 4.

**Exit criteria** (verbatim from PLAN_0_1_1 §Phase D): five scenarios.

**Commit:** `PLAN_0_1_1 Phase D: DecisionExtractor v0.1.1 — new vvdec: predicates`.

### Work unit 10 — v0.1.1 Phase E: docs, CHANGELOG, VERSION → **tag 0.1.1**

**Goal:** v0.1.1 acceptance signal. The new epistemic-schema-integration spec is green; the v0.1.0 suite is unchanged (additive proof).

**Inputs:** PLAN_0_1_1 §Phase E.

**Spec first:** `spec/vv/decision/epistemic_schema_integration_spec.rb` — full round-trip: schema load → `deliberate` with schema → tripwire fires → persisted in column → re-read via `Decision#epistemic_schema` → `conform_now!` → new vvdec: predicates land in Silver.

**Deliverable:**
- Integration spec green.
- `CHANGELOG.md` — `0.1.1` section with per-phase entries; drop `(unreleased)`.
- `README.md` — add the "Epistemic schemas" section above "Sketch of the surface"; one end-to-end YAML example + `deliberate(..., epistemic_schema:)` call.
- `CONSUMER_REQUIREMENT_MM.md` — extend with the new reserved `kind:` string `decision_tripwire` and the recommended `config/decision_schemas/*.epistemic.yml` location.
- `VERSION` → `0.1.1`.
- `lib/vv/decision/version.rb` → `VERSION = "0.1.1"`.

**Acceptance:** PLAN_0_1_1 §Acceptance signal items 1–7 are met. Item 8 (the first-consumer-PR with a real `epistemic_schema:` argument in mm-server) is tracked here under work unit 11.

**Tag:** `v0.1.1` annotated tag. Push the tag.

**Commit:** `PLAN_0_1_1 Phase E: integration spec + docs; tag v0.1.1`.

### Work unit 11 — v0.1.2 first-consumer-PR (`mm-server` integration) → **tag 0.1.2**

**Goal:** The substrate's `mm-server` Gemfile carries `vv-decision` via path source. At least one agent path exercises `deliberate(..., epistemic_schema:)` against tagged 0.1.1. This is the v0.1.2 acceptance signal.

**Gate:** This work unit edits files **outside** `vendor/vv-decision/`. Confirm scope with the user before any edit. The path-vendored siblings (`vv-memory`, `vv-graph`) are read-only per the sequencing principles; only `mm-server`'s own files (its `Gemfile`, its agent-path source file, optionally a `config/decision_schemas/*.epistemic.yml`) are edited.

**Inputs:** PLAN_0_1_0 §Acceptance signal item 7 + PLAN_0_1_1 §Acceptance signal item 8.

**Spec first:** A `mm-server`-side spec that exercises the agent path end-to-end. The spec lives in `mm-server`'s test suite, not in `vv-decision`'s. The shape: instantiate the agent's scope (`Session` or `Workspace`), call its existing entrypoint, assert that a `Vv::Decision::Decision` row landed, assert that the epistemic-schema column carries the expected payload, assert that the agent's response references the schema's verified domains.

**Deliverable:**
- `mm-server`'s `Gemfile`: add `gem "vv-decision", path: "../vendor/vv-decision"` (exact path TBD by the substrate's vendor layout).
- One real agent path that calls `Vv::Decision.deliberate(scope:, context:, epistemic_schema:) do |ctx| … ctx.decide!(...) end`.
- One `config/decision_schemas/<agent>.epistemic.yml` file (~1–3 KB) declaring verified domains, knowledge gaps, and at least two tripwires (one `:flag`, one `:append_confidence_score` — `:refuse_and_flag` is opt-in only after the operator trusts the firing pattern; per PLAN_0_1_1 §Risks row 2).
- Update `vv-decision`'s `CONSUMER_REQUIREMENT_MM.md` to reference the actual integration path (`mm-server/app/<...>`).
- `vv-decision`'s `VERSION` → `0.1.2`.
- `lib/vv/decision/version.rb` → `VERSION = "0.1.2"`.
- `CHANGELOG.md` — `0.1.2` section: "First-consumer integration: `mm-server` wires `Vv::Decision.deliberate(..., epistemic_schema:)` on the `<agent>` path. No gem-side contract changes."

**Acceptance:**
- The `mm-server`-side spec is green against tagged 0.1.1's surface.
- A real production-path agent invocation (not a spec-only call) lands a `Decision` row with a non-empty `epistemic_schema` column.
- No vv-decision contract surface moves at 0.1.2 — this release is purely the consumer-integration milestone.

**Tag:** `v0.1.2` annotated tag. Push the tag.

**Commit (vv-decision side):** `v0.1.2: first-consumer integration milestone (mm-server)`.

## Checkpoints

The implementer pauses for user confirmation at each of these checkpoints, even if the immediately-prior work unit's exit criteria are met:

| Checkpoint | After work unit | Why |
|---|---|---|
| **C1** — gates G1 + G2 + G3 results | (before unit 1) | If any gate fails, the user must decide whether to amend the design plan or escalate. Work cannot proceed silently. |
| **C2** — v0.1.0 tag review | 5 | The substrate is about to commit to a frozen v0.1.0 surface. The user reviews the README + CHANGELOG before the tag is pushed. |
| **C3** — v0.1.1 tag review | 10 | Same as C2 for the v0.1.1 surface. The additivity proof (full v0.1.0 suite unchanged) is presented to the user. |
| **C4** — mm-server edit scope | (before unit 11) | The implementer is about to edit files outside `vendor/vv-decision/`. The user confirms which agent path is the integration target and which scope type carries the call. |
| **C5** — v0.1.2 tag review | 11 | Same as C2/C3 for the v0.1.2 milestone. Plus: confirm the `mm-server`-side spec is green and the production-path agent invocation has landed (not just spec-only). |

## Out of scope for this implementation plan

- **Adding any surface not designed in PLAN_0_1_0 / PLAN_0_1_1.** If the implementation needs a helper class or constant the design didn't name, the design plan is updated first.
- **Modifications to `vendor/vv-memory/` or `vendor/vv-graph/`.** Sibling-gem-surface gaps stop work and prompt a user conversation; they do not become cross-repo edits inside this plan's scope.
- **`Vv::Memory.recall(...)` facade integration, action emission, causal traversal, Curator/Gold integration, class-level analytical facades.** All v0.2.0+ per PLAN_0_1_0 §Out of scope; not touched here.
- **Automated schema generation, schema inheritance, SHACL integration.** All v0.2.0+ per PLAN_0_1_1 §Out of scope; not touched here.
- **Publishing to rubygems.org.** Path-vendored under `vendor/vv-decision/` per PLAN_0_1_0 §Out of scope.
- **Documentation rewrites beyond what each Phase F-equivalent calls for.** README + CHANGELOG + CONSUMER_REQUIREMENT_MM only; no separate architecture documents.

## Risks specific to implementation (not design)

| Risk | Mitigation |
|---|---|
| Gate G2 reveals the extractor revision convention is incompatible. The design plans pin `"vv-decision/v0.1.0/DecisionExtractor"` but vv-memory's convention is `<class-shortname>-v<integer>`. | Treat this as a known mismatch. Work unit 3 begins by amending PLAN_0_1_0 §Phase D and the contract table (with user confirmation) before any code lands. The amendment is mechanically trivial; the substantive risk is that operators reading the design plan get the wrong revision string. The contract-table row is the load-bearing surface; update it once and reference it from work unit 9. |
| The Phase A `MissingDependency` guard fires in CI because the suite boots without vv-memory installed. | Already mitigated by `lib/vv/decision.rb`'s `begin/rescue LoadError` around `require "vv/memory"` and the harness's `:requires_extension` skip pattern. Confirmed reading the file. |
| The Phase B migration uses `:jsonb` but SQLite (the harness DB) only knows `:json`. | The harness's `spec/support/schema.rb` already uses `t.text` / `t.string` for the substrate tables; the migration shipped in `db/migrate/` uses `:jsonb`. Operators on PostgreSQL get jsonb; SQLite operators get the same column with `:json` semantics. Confirm during work unit 1 by reading how `vv-memory` migrations handle the same case. |
| The integration spec (work unit 5) needs the compiled `sqlite-sparql` extension. The implementer's environment may not have it built. | The harness's `:requires_extension` tag already handles the skip-with-hint case. The implementer runs `bundle exec rspec` once before work unit 1 to confirm the extension is available; if not, follows the build hint in `spec/support/extension_environment.rb`. If the build fails, stop and ask the user. |
| The work units' specs collectively grow large enough to slow the suite below the acceptable inner-loop time. | Tag the integration specs `:slow`; the default rspec invocation excludes them. CI runs the full suite. (No spec-runtime budget pinned in v0.1.0 / v0.1.1; if this becomes a concern, defer to a v0.1.x housekeeping release.) |
| The implementer over-implements — adds helper methods, refactors existing code, or introduces abstractions the design didn't ask for. | Each work unit's "Deliverable" list is exhaustive. Anything not on the list is out of scope for that unit. The user reviews each commit; "scope creep" is grounds for rolling back. |
| The implementer under-implements — defers exit criteria as "follow-up." | Exit criteria are copied verbatim from the design plans and must all pass before the work unit's commit lands. No "follow-up" issue tracker; if an exit criterion can't be met, the design plan is amended (with user confirmation) before the work unit closes. |
| Work unit 11 (mm-server integration) discovers that the substrate's scope shape doesn't match `Vv::Memory::Scoped` cleanly. | Stop. This indicates a layering-correction ask back to vv-memory, not a vv-decision concern. Ask the user before editing anywhere. |
| The `0.1.2` tag is pushed before a real production-path agent invocation has landed (only the spec is green). | Tag at the moment work unit 11's full deliverable list is checked off, NOT at spec-green. The deliverable list explicitly requires "a real production-path agent invocation (not a spec-only call) lands a `Decision` row." Checkpoint C5 enforces this. |

## Acceptance signal for the implementation plan as a whole

1. Work units 1–5 land; tag `v0.1.0` is pushed; PLAN_0_1_0 §Acceptance signal items 1–6 are met.
2. Work units 6–10 land; tag `v0.1.1` is pushed; PLAN_0_1_1 §Acceptance signal items 1–7 are met. The v0.1.0 spec suite passes unchanged (additivity proof).
3. Work unit 11 lands; tag `v0.1.2` is pushed; the substrate has at least one production-path agent invocation that exercises `Vv::Decision.deliberate(..., epistemic_schema:)` against the tagged surface.
4. The CHANGELOG records each release with the per-phase entries that map back to the work units of this plan.
5. The README documents the actually-shipped surface (post-v0.1.1) — the `deliberate(...)` entrypoint, the four flow methods, the epistemic-schema kwarg, the three tripwire actions, and the five built-in patterns.
6. No design-plan contract row moved without an explicit amendment + user confirmation. (Implementation discoveries that triggered amendments are recorded in the design plan's git history; this plan's git history records the work units that followed.)

## Cross-references

- `./PLAN_0_1_0.md` — the v0.1.0 design plan. Source of truth for work units 1–5.
- `./PLAN_0_1_1.md` — the v0.1.1 design plan. Source of truth for work units 6–10.
- `../../../../docs/research/DecisionLayer.md` — the architectural finding behind the gem.
- `../../../../docs/research/DecisionContext.md` — the 2KB-file finding behind the epistemic-schema surface.
- `../../README.md` — this gem's README. Updated at work units 5 (post-v0.1.0) and 10 (post-v0.1.1).
- `../../CHANGELOG.md` — versioned release log. Updated at the end of each work unit, not deferred to phase F / phase E.
