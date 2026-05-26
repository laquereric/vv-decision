# vv-decision

The **third concern above memory** in the MagenticMarket agent
substrate: the agent's *reasoning loop as a first-class lifecycle*.
Where [`vv-graph`](../vv-graph) owns triples and
[`vv-memory`](../vv-memory) owns the medallion lifecycle that
records what happened, **vv-decision** owns the forward-acting
flow — context → query → reasoning → decision → action → impact —
and persists each step's provenance as a `Decision` aggregate
root.

> **Status: v0.1.0 — unreleased.** Source is in place per
> [`docs/plans/PLAN_0_1_0.md`](docs/plans/PLAN_0_1_0.md); the gem
> is not yet published to RubyGems. The architectural finding that
> motivates it lives in
> [`docs/research/DecisionLayer.md`](../../docs/research/DecisionLayer.md).
> The MagenticMarket substrate is the first consumer.

## Architecture sidebar — three layers, not two

```
   ┌──────────────────────────────────────────────────────────┐
   │ vv-decision (this gem)                                   │
   │   deliberate(context:) → context → query → decide → act  │
   │   Decision aggregate root: flow record, not triple row   │
   └──────────────────────────▲───────────────────────────────┘
                              │ recall + record-as-episode
   ┌──────────────────────────┴───────────────────────────────┐
   │ vv-memory                                                │
   │   Bronze (Episode) → Silver (Conformer) → Gold (Curator) │
   │   recall(scope:, query:) — traversal                     │
   └──────────────────────────▲───────────────────────────────┘
                              │ Sparql + EtherealGraph + Scope
   ┌──────────────────────────┴───────────────────────────────┐
   │ vv-graph                                                 │
   │   triples + reasoning + validation                       │
   └──────────────────────────────────────────────────────────┘
```

| Layer | Concern | Stays-in-its-lane test |
|---|---|---|
| **Graph** — [`vv-graph`](../vv-graph) | Storage, query, reasoning, validation of triples. SPARQL, OWL 2 RL, SHACL Core, SHACL Rules, ChangeSet, Scope. | Knows nothing about "what produced this triple" or "what we'll do with it." |
| **Memory** — [`vv-memory`](../vv-memory) | Medallion lifecycle — Bronze (what happened) → Silver (what we believe, with RDF-star provenance) → Gold (what we commit to). | Backward-looking. Records *into* the past tense. |
| **Decision** — `vv-decision` *(this gem)* | The flow: context → query → reasoning → decision → action → impact. Each step has its own provenance. | Forward-acting. Reads from the memory layer and writes back into it, but owns the agent's reasoning loop as a first-class lifecycle. |

Dependencies flow strictly down. No layer reaches past the one
immediately below it.

## Sketch of the surface (not a contract)

```ruby
# Deliberate over a context. The block has access to `recall` (the
# vv-memory traversal) and `decide!` (the commitment). The
# `deliberate` call returns a Decision aggregate root persisted
# atomically with the flow steps.
session.deliberate(context: "user asked: should we cancel order 42?") do |ctx|
  ctx.recall(query: "what do we know about order 42?", depth: :silver) => evidence

  ctx.consider(option: :cancel,  grounded_in: evidence.where(predicate: "mm:status"))
  ctx.consider(option: :hold,    grounded_in: evidence.where(predicate: "mm:has_dependency"))
  ctx.consider(option: :proceed, grounded_in: evidence.where(predicate: "mm:has_committed_funds"))

  ctx.reason_with(model: :claude_opus_4_7, prompt: <<~PROMPT)
    Given the evidence above, which option is consistent with the user's stated goal?
  PROMPT

  ctx.decide!(option: :hold, because: "active dependency on order 17 not yet resolved")
end
# => Vv::Decision::Decision aggregate root
```

```ruby
# Read-side traversal — flows, not triples.
decision.trace_back               # decisions whose actions caused this decision's context
decision.alternatives_considered  # the rejected options + their grounded_in evidence
decision.impact                   # downstream episodes the action produced
decision.evidence_slice           # the recall result the decision was grounded in
decision.reasoning_trace          # the model call(s) + prompt + completion
Vv::Decision.find_precedents(context: "...", scope: workspace, k: 5)
```

### Aggregate root, not a Storable shape

The persistence story reuses the medallion rather than duplicating it:

- **Bronze** — `deliberate(...)` appends one or more episodes
  (`kind: "decision_context"`, `"decision_query"`,
  `"decision_reasoning"`, `"decision_outcome"`, `"decision_action"`)
  into `vv-memory`'s Bronze. These ARE agent acts; the medallion
  is exactly where they belong.
- **Silver** — a `Vv::Memory::Conformer::Extractor` subclass
  (`DecisionExtractor`) turns the decision episodes into typed
  triples with the standard `vvmem:` provenance plus a new
  `vvdec:` namespace for decision-specific predicates
  (`vvdec:grounded_in`, `vvdec:alternative_to`, `vvdec:caused_by`,
  `vvdec:reasoned_with`). RDF-star annotations link the outcome
  triple back to the originating episodes.
- **Gold** *(later)* — `vv-memory`'s Curator promotes
  high-confidence decision patterns into curated commitments
  (e.g., a recurring "in this context, the agent consistently
  chose X" pattern).

`vv-decision` owns the **aggregate root** — the Ruby-side
`Decision` object that holds references across all those episodes
+ triples + annotations and presents them as one coherent flow.
The storage substrate is `vv-memory`'s, not its own.

## Why a separate gem (vs. a `Vv::Memory::Conformer::DecisionExtractor`)

1. **Different directional invariant.** `deliberate(...)` is
   forward-acting — it triggers recall, takes reasoning steps,
   may invoke side-effecting actions. The Conformer is
   backward-acting — it reads already-recorded episodes and
   writes derived facts.
2. **Aggregate-root lifecycle methods** (`#trace_back`,
   `#alternatives_considered`, `#impact`) read across multiple
   medallion tiers. Putting them on the Conformer would widen
   `vv-memory`'s responsibility past "promotion" into "querying
   as an agent operation."
3. **`vvdec:` vocabulary** is a separate naming concern from
   `vvmem:` and should be owned by the layer that emits it.

## Dependencies

- **[`vv-memory`](../vv-memory)** — Bronze episode emission, Silver
  extraction (the Conformer's `Extractor` interface is the
  integration point), Gold curation (later), and `recall(...)`.
- **[`vv-graph`](../vv-graph)** — direct dependency on
  `Vv::Graph::Scope` for cross-graph operations + a SPARQL surface
  for the read-side aggregate methods.

`vv-decision` does **not** depend on `sqlite-sparql` directly —
the same layering rule `vv-memory` pinned in
[`../vv-graph/CONSUMER_REQUIREMENT_VV.md`](../vv-graph/CONSUMER_REQUIREMENT_VV.md)
extends one layer up: a decision gem consumes `vv-memory` +
`vv-graph`, not the engine.

## License

MIT. Same as the rest of the MagenticMarket substrate.

## Cross-references

- [`docs/research/DecisionLayer.md`](../../docs/research/DecisionLayer.md) —
  the architectural finding that motivates this gem; open questions
  tracked there until a PLAN lands here.
- [`semantica-agi/semantica`](https://github.com/semantica-agi/semantica) —
  the upstream Python project whose decision-intelligence DSL
  motivated the original PLAN_0.14.0, and whose decision-as-data
  framing this gem pushes back against.
