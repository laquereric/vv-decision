# Consumer requirements — MagenticMarket substrate

What the MagenticMarket substrate (the Rails app; "MM" hereafter) consumes
from `vv-decision` — the reasoning-loop-as-lifecycle gem
(`Vv::Decision.deliberate`, the `Decision` aggregate).

- MM repo: <https://github.com/laquereric/magentic-market-ai>
- MM consumer: `server/lib/compliance/sweep_process.rb`
  (`Compliance::SweepProcess`'s `:triage` step), introduced by
  `docs/plans/PLAN_0_93_4.md` Phase C — per-violation triage records a
  `Decision` (consider → decide!).
- This gem: [`README.md`](README.md).

## How MM pins this gem

```ruby
# server/Gemfile
gem "vv-decision", path: "../vendor/vv-decision"
```

`vendor/vv-decision` is a tracked git submodule pinned by SHA
(path-sourced under the substrate-mutual-evolution doctrine). Its deps
(`vv-memory >= 0.2.0`, `vv-graph ~> 0.15`, rails `>= 8.0`) resolve against
MM's existing pins. Its engine's `after_initialize` registers a
`DecisionExtractor` with vv-memory's Conformer `StrategySelector` — MM's
vv-memory provides the matching `register(kind:, extractor_class:)` API.

## Surfaces MM consumes

`Compliance::SweepProcess`'s `:triage` step consumes the deliberation
entrypoint + its block context:

- **`Vv::Decision.deliberate(scope:, context:, provenance_id: nil, &block)`**
  → returns a `Vv::Decision::Decision`. `scope` must include
  `Vv::Memory::Scoped`; `context` is a non-blank String. AR-backed (opens a
  transaction, records Bronze episodes, persists the Decision).
- The yielded **`DeliberationContext`**: `consider(option:, grounded_in:,
  rejected_because:)` and `decide!(option:, because:)` (one `decide!` per
  deliberate). MM considers `:auto_fix` / `:defer` / `:escalate` and decides
  one per compliance violation.
- The returned **`Decision`** readers MM reads: `#decided_option` and
  `#because` (the triage record copies these).
- **Declared, not yet exercised live:** the persistent flow needs a real
  `Vv::Memory::Scoped` scope + DB and runs only under a real
  `Vv::Process.run!` (deferred — PLAN_0_93_4 Phase B). MM unit-tests the
  triage policy through an injected deliberator; the live deliberate lands
  when the persistent run wires up.

## What would break MM if it changed

- Renaming `Vv::Decision.deliberate` or changing its
  `(scope:, context:, provenance_id:, &block)` signature.
- Changing `DeliberationContext#consider(option:, …)` / `#decide!(option:,
  because:)` — MM's triage block calls them by exact keyword shape.
- Removing/renaming `Decision#decided_option` or `Decision#because` — MM's
  triage record reads both.
- The engine's `register_extractor!` calling a vv-memory Conformer API that
  no longer matches (would crash MM boot, as a require/registration drift).

## What MM tolerates

- Internal `Decision` / Bronze-episode / DecisionExtractor changes that
  preserve the `deliberate` + `consider`/`decide!` + `decided_option`/
  `because` surface.
- The five reserved `decision_*` Bronze episode kinds being emitted (MM
  excludes them from plain episode views as needed).
- New `consider` metadata / additive `Decision` columns.
- Performance improvements.

## See also

- `server/lib/compliance/sweep_process.rb` — MM's consumer (the `:triage` step).
- `docs/plans/PLAN_0_93_4.md` — Phase C (this consumption) + Phase D (which
  will flip some triage decisions to `:auto_fix`).
- `vendor/vv-memory/CONSUMER_REQUIREMENT_DS.md` — vv-decision's own consumer
  view of vv-memory (the reciprocal direction).
