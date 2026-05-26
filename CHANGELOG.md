# Changelog

## 0.1.0 — (unreleased)

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
