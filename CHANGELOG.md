# Changelog

## 0.1.0 — 2026-05-28

First shippable release. Stands up the **third concern above
memory**: the agent's reasoning loop as a first-class lifecycle.
Reuses `vv-memory`'s Bronze (for decision-flow episodes) and
Silver (for `vvdec:`-namespaced triples emitted via a
`DecisionExtractor` Conformer subclass); no new storage tier.

See [docs/plans/PLAN_0_1_0.md](docs/plans/PLAN_0_1_0.md) for the
architectural sketch and the per-phase exit criteria this release
satisfies.

- **Phase A — gem skeleton + Engine.** `vv-decision.gemspec` pins
  `vv-memory >= 0.2.0` (the Conformer Extractor interface is the
  primary integration point) + `vv-graph >= 0.13` (the
  `Vv::Graph::Scope` read-side surface) + `activerecord /
  railties >= 8.0`. `lib/vv/decision.rb` is the top-level entry.
  `Vv::Decision::Engine` isolates the namespace and registers an
  `after_initialize` guard that raises
  `Vv::Decision::Errors::MissingDependency` if either
  `Vv::Memory::Scoped` or `Vv::Memory::Conformer::Extractor` is
  undefined (with the verbatim hint *"bundle vv-memory 0.2.0+
  alongside vv-decision"*). Spec harness mirrors `vv-memory`'s
  pattern — an in-process AR environment, no full
  `Rails::Application` boot. Five pinned error classes:
  `MissingDependency`, `InvalidDeliberation`, `AlreadyDecided`,
  `RecallDepthUnsupported`, `NoDecisionMade`.
- **Phase B — `Vv::Decision::Decision` aggregate root.** AR model
  on `vv_decision_decisions` (migration `20260525000001`). One row
  per `deliberate(...)` call; polymorphic `scope` mirrors
  `Vv::Memory::Episode`'s shape; two FK columns reference
  `vv_memory_episodes.id` (context + outcome episodes — relies on
  vv-memory's pinned table/PK, CR_DS B5). `alternatives` /
  `reasoning_payload` are `json` columns. No state machine —
  `decided_at` doubles as the committed flag. Scopes: `decided`,
  `since`, `for_option`; `#decided?` / `#option`.
- **Phase C — `deliberate` + `DeliberationContext` + `EvidenceSlice`.**
  `Vv::Decision.deliberate(scope:, context:, provenance_id:, &block)`
  wraps the flow in a transaction (block raise ⇒ full rollback).
  `DeliberationContext#recall` (Silver-only thin recall; `:gold` /
  `:bronze` raise `RecallDepthUnsupported`), `#consider`,
  `#reason_with`, `#decide!` (one commit per call; second raises
  `AlreadyDecided`). The five reserved Bronze kinds export as
  `Vv::Decision::EPISODE_KINDS`. `EvidenceSlice` is a read-only
  `#where` / `#iris` / `#count` value object over recall rows.
- **Phase D — `DecisionExtractor` (Conformer subclass).** Promotes
  `decision_outcome` episodes into `vvdec:`-namespaced Silver
  triples (headline `rdf:type vvdec:Decision` + context /
  decided_option / because / decided_at / grounded_in /
  alternative_to / reasoned_with). Registered against the
  `"decision_outcome"` kind via
  `Vv::Memory::Conformer::StrategySelector.register` (vv-memory
  v0.2.2's registry surface) in the Engine's `after_initialize`;
  `Vv::Decision.register_extractor!` exposes the idempotent
  registration for non-Rails contexts. Revision string
  `"vv-decision/v0.1.0/DecisionExtractor"` (accepted under
  vv-memory's relaxed CR_DS B2 convention). **Note:** vv-memory
  shipped `StrategySelector.register(kind:, extractor_class:)`,
  NOT the `ExtractorRegistry.unregister(...)` this plan originally
  sketched — there is no per-class unregister; opt-out is via a
  custom `StrategySelector`. See PLAN_0_1_0 Phase D.
- **Phase E — read-side traversal.** `Decision#trace_back`
  (timeline-shaped: prior same-scope decisions whose outcome
  predates this context), `#alternatives_considered` (rejected
  options enriched with a re-queried `EvidenceSlice`), `#impact`
  (same-scope episodes after `decided_at`, as a Relation),
  `#evidence_slice` (union of grounding IRIs, retracted IRIs omit
  silently), `#reasoning_trace`.
- **Phase F — integration spec, `bin/check`, docs.**
  `deliberate_integration_spec.rb` is the acceptance signal: the
  full `deliberate → five-kind Bronze → conform_now! → vvdec:
  Silver + vvmem: provenance → read-side traversal →
  checkpoint/evict/hydrate` round-trip. Suite: 42 examples, 0
  failures against the live engine. Also fixed two pre-existing
  harness bugs the now-loadable Engine exposed: `version_spec`'s
  VERSION path (`../../../../` → `../../../`) and `engine_spec`'s
  brittle `initializers.size` assertion (now exercises the
  boot-time `register_extractor!` registration directly).
