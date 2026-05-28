# PLAN_0_1_3 — `vv-decision` structured decomposition

> *Adds **structured decomposition** — the OWL 2 + SWRL three-step
> reasoning pattern (entity identification → assertion extraction →
> symbolic rule application) from Sadowski & Chudziak's
> "Structured Decomposition for LLM Reasoning" (arXiv:2601.01609,
> January 2026) — as an additive, optional shape on
> `deliberate(...)`. Motivated by the paper's finding that
> structured decomposition with SWRL verification achieves
> statistically significant F1 gains over few-shot prompting
> (79.8% vs 75.2% averaged across 33 model-task combinations
> spanning legal hearsay determination, scientific method
> application, and clinical trial eligibility — with notably
> higher recall: 84.7% vs 69.0%). v0.1.3 is **purely additive**
> on v0.1.0 + v0.1.1: the existing five-method flow still works,
> the `epistemic_schema:` kwarg still works, and existing callers
> see no behavior change. The bet: the layer that owns the
> **forward-acting reasoning loop** is also the layer that should
> structure the loop into TBox / ABox / rules when the task
> domain admits it — and refuse to structure it when the task
> domain does not (the paper's URTI negative result: F1 0.145
> when structured decomposition is misapplied to a statistical
> rather than rule-governed task).*

## Anchors

| Anchor | Where | Role |
|---|---|---|
| `docs/research/StructuredDecomp.md` (parent repo) | `../../../../docs/research/StructuredDecomp.md` | The research paper that motivates this release. The three-step decomposition (entity identification → assertion extraction → rule application), the two suitability criteria (rule-expressible boundary + formalisable predicates), the complementary-predicates pattern (mitigates LLM confirmation bias under OWA), and the URTI negative result (suitability matters) are all sourced verbatim from here. |
| `docs/research/DecisionContext.md` (parent repo) | `../../../../docs/research/DecisionContext.md` | The 2KB-file finding behind v0.1.1's epistemic schemas. Structured decomposition is compositional with epistemic schemas — see "Composability with v0.1.1" below. |
| `docs/research/DecisionLayer.md` (parent repo) | `../../../../docs/research/DecisionLayer.md` | The original architectural finding behind this gem. Structured decomposition slots into the "reasoning" box of the forward-acting flow; the three sub-steps decompose what was a single `reason_with(...)` call into a populated ABox + a symbolic classification. |
| `./PLAN_0_1_0.md` | this directory | The v0.1.0 design baseline. Every v0.1.0 contract row still holds at v0.1.3. |
| `./PLAN_0_1_1.md` | this directory | The v0.1.1 design baseline (epistemic schemas). Every v0.1.1 contract row still holds at v0.1.3. |
| `./PLAN_0_1_2.md` | this directory | The implementation plan. Work units 12–17 (extending the existing 1–11) execute this PLAN; gate G4 (verify reasoner-adapter integration assumption) precedes work unit 14. |
| `vendor/vv-memory/docs/plans/PLAN_0.2.0.md` | sibling | `Vv::Memory::Conformer::Extractor`. v0.1.3's `DecisionExtractor` revision bumps to v0.1.3 (`"decision-v3"` per the convention reconciliation tracked in `CONSUMER_REQUIREMENT_DS.md` B2). |

## Current state baseline (2026-05-26)

v0.1.1 (designed; awaiting PLAN_0_1_2 execution) extends
v0.1.0's reasoning-loop record with the `epistemic_schema:`
kwarg, a TripwireInterpreter, and four new `vvdec:` predicates.
`ctx.reason_with(model:, prompt:, completion:)` remains a single
opaque LLM-trace recorder: one model call, one prompt, one
completion. The operator's interpretive work — what entities
the LLM identified, what assertions it extracted, what rule it
applied — is unstructured inside the `completion` blob.

The Sadowski–Chudziak paper reframes that. Rule-governed
domains (their three case studies: legal hearsay determination,
scientific method application, clinical trial eligibility) admit
a **three-step decomposition** where:

1. **Entity identification** — the LLM extracts individuals from
   text matching ontology-defined classes (an LLM call producing
   ABox class-membership assertions).
2. **Assertion extraction** — the LLM evaluates ontology-defined
   property predicates against those entities (a second LLM
   call producing ABox property assertions, each with a natural
   language justification).
3. **Rule application** — a symbolic reasoner (Pellet in the
   paper) applies SWRL rules over the populated ABox; the
   classification outcome is the deterministic result of the
   rule's antecedent being satisfied.

The empirical finding: this decomposition yields F1 79.8%
(structured decomposition with SWRL verification) versus 75.2%
(few-shot) and 74.1% (chain-of-thought) averaged across 33
model-task combinations, with statistically significant
improvements in all three domains. The ablation (SD-Direct,
which bypasses the symbolic reasoner) drops to F1 70.1%,
demonstrating that the symbolic verification step provides
substantial benefit beyond structured prompting alone.

v0.1.3 of this gem gives the forward-acting reasoning loop the
shape to record and verify that three-step decomposition when
the operator opts in — and refuses to pretend the decomposition
applies when the task domain is statistical rather than
rule-governed (the paper's URTI counter-example).

## Architectural shape (delta from v0.1.1)

```
   v0.1.1 flow                                  v0.1.3 addition

   deliberate(scope:, context:,                 deliberate(scope:, context:,
       epistemic_schema:, &block)                   epistemic_schema:,
       │                                            task_ontology: ontology, &block)
       ▼                                            │
   ┌───────────────────┐                            ▼
   │ DeliberationCtx   │                     ┌────────────────────────────────────┐
   │   recall          │                     │ Vv::Decision::TaskOntology         │
   │   consider        │  ── decomposed ──── │   tbox:        { classes,          │
   │   reason_with     │      by             │                  object_properties,│
   │   decide!         │                     │                  data_properties } │
   └─────────┬─────────┘                     │   swrl_rules:  [ {antecedent,      │
             │                               │                  consequent}, ... ]│
             │ ⇣ new flow methods (additive) │   entity_specs:    { ... }         │
             │                               │   assertion_specs: { ... }         │
             ▼                               │   complementary:   true|false      │
   ┌──────────────────────────────────────┐  └────────────────────────────────────┘
   │ ctx.identify_entities!(spec:, text:, │                  │
   │                       entities:)     │  ← consults TBox │
   │   → Bronze "decision_entity_id"      │                  │
   │                                      │                  │
   │ ctx.extract_assertions!(spec:,       │                  │
   │                        entities:,    │                  │
   │                        assertions:)  │  ← consults TBox │
   │   → Bronze "decision_assertion_ext"  │                  │
   │                                      │                  │
   │ ctx.apply_rules!(ontology:,          │                  │
   │                  reasoner:)          │  ← applies SWRL  │
   │   → Bronze "decision_rule_app"       │                  │
   │   → returns ClassificationOutcome    │                  │
   └──────────────────────────────────────┘
             │
             ▼
   Bronze tier:  +3 new episode kinds  "decision_entity_identification"
                                       "decision_assertion_extraction"
                                       "decision_rule_application"
   Aggregate:    +1 new column         task_ontology         (jsonb)
                 +1 new column         populated_abox        (jsonb, default [])
                 +1 new column         classification_outcome (jsonb, default {})
   Silver tier:  +5 new predicates     vvdec:applies_ontology
                                       vvdec:populated_individual
                                       vvdec:asserted_property
                                       vvdec:reasoner_classified
                                       vvdec:complementary_predicate_used
   Tripwire:     +1 new built-in pattern  "task_not_rule_governed"
```

**Nothing in the v0.1.0 or v0.1.1 surface moves.** Old callers
(no `task_ontology:` kwarg, no `identify_entities!`/
`extract_assertions!`/`apply_rules!` calls) get exactly the
v0.1.1 behavior. The three new flow methods are optional; the
five-method flow from v0.1.0 (`recall` / `consider` /
`reason_with` / `decide!`) still works exactly as before.
Structured decomposition supplements the flow; it does not
replace it.

## Composability with v0.1.1 (epistemic schemas)

A single `deliberate(...)` call may carry **both** an
`epistemic_schema:` and a `task_ontology:`. The two surfaces
constrain different aspects:

- **Epistemic schema** constrains *what the model talks about*
  — verified_domains, knowledge_gaps, tripwires. It bounds the
  LLM call.
- **Task ontology** constrains *how the model reasons* —
  TBox-defined entities, ABox-populated assertions, SWRL rules.
  It shapes the decomposition.

The two are orthogonal. A deliberation may have:

| Configuration | Epistemic schema | Task ontology | Behavior |
|---|---|---|---|
| Plain v0.1.0 | — | — | Five-method flow, no constraints. |
| v0.1.1 | ✓ | — | Five-method flow, tripwires fire on patterns. |
| v0.1.3 (rule-governed) | — | ✓ | Three-step decomposition + five-method flow, no schema constraints. |
| v0.1.3 (both) | ✓ | ✓ | Three-step decomposition + tripwires; the `task_not_rule_governed` tripwire (Phase E) and the epistemic schema's other tripwires fire independently. |

The two kwargs are kwarg-independent; passing one does not
require the other. Operators choose what their task admits.

## Suitability — load-bearing

The paper makes the case (Table 2 + the URTI negative result):
**structured decomposition is a targeted approach, not a
general-purpose improvement**. Two necessary criteria:

1. **Rule-expressible decision boundary** — the classification
   must be fully determined by a logical formula over
   extractable predicates. (The URTI medical-diagnosis task
   fails here: symptom profiles overlap across diagnoses; the
   true boundary is statistical.)
2. **Formalisable predicates** — the domain must permit
   decomposition into discrete predicates whose logical
   composition captures necessary and sufficient conditions.

If either fails, structured decomposition harms accuracy. The
paper's URTI experiment: F1 0.145 (structured decomposition)
vs 0.979 (few-shot). v0.1.3 ships **runtime safety nets**
against this misapplication:

- The `Vv::Decision::TaskOntology` value object's
  `#suitable?(:rule_expressible_boundary)` and
  `#suitable?(:formalisable_predicates)` methods return Booleans
  the operator can assert in their own pre-flight checks. The
  gem cannot verify these criteria programmatically (no
  automatable test for "is this domain rule-governed"); the
  methods return whatever the operator asserted at ontology
  construction time via the `suitability:` kwarg. The value
  object refuses to construct without explicit assertions —
  forcing the operator to pause and consider.
- The Phase E built-in tripwire pattern
  `task_not_rule_governed` fires at `apply_rules!` time if the
  task ontology declares fewer than one SWRL rule whose
  consequent is the target class, OR if the
  `suitability_attestation:` kwarg on `apply_rules!` is missing
  (operators must re-attest at use-site, not only at
  ontology-load-site).
- The README documents the suitability criteria prominently
  with the URTI counter-example, framed as a refusal-to-apply
  rule.

## Scope

### Phase A — `Vv::Decision::TaskOntology` value object

A small immutable value object loaded from OWL 2 XML, Turtle, or
a Hash-shaped Ruby description. Validates shape and the
suitability attestation at construction time. Frozen after build.

```ruby
ontology = Vv::Decision::TaskOntology.load_owl_xml(
  File.read("config/order_cancellation.owl"),
  suitability: {
    rule_expressible_boundary: true,
    formalisable_predicates: true,
    rationale: "Order cancellation eligibility is defined by " \
               "an explicit policy document (Rule 47.B of " \
               "MagenticMarket Cancellation Protocol). The " \
               "predicates (order_age, payment_status, " \
               "dependency_count) are formalisable.",
  },
)
```

#### Constructors

- `.load_owl_xml(string, suitability:)` — parses OWL 2 XML.
- `.load_turtle(string, suitability:)` — parses Turtle (with
  SWRL rules per the W3C SWRL/Turtle convention).
- `.from_hash(hash, suitability:)` — accepts a Hash with the
  shape documented under "TBox + SWRL hash form" below; runs
  validation; freezes.

All three constructors require the `suitability:` kwarg as a
non-nil Hash with both keys. Construction raises
`Vv::Decision::Errors::SuitabilityNotAttested` otherwise.

#### TBox + SWRL hash form

```ruby
{
  tbox: {
    classes: ["Order", "CancellableOrder", "ActiveDependency"],
    object_properties: {
      "hasDependency" => { domain: "Order", range: "ActiveDependency" },
    },
    data_properties: {
      "orderAge"      => { domain: "Order", range: "xsd:integer" },
      "paymentStatus" => { domain: "Order", range: "xsd:string" },
    },
  },
  swrl_rules: [
    {
      antecedent: [
        { class: "Order",  variable: "?o" },
        { property: "orderAge", subject: "?o", value: ">", "30" },
        { property: "paymentStatus", subject: "?o", value: "=", "refundable" },
      ],
      consequent: { class: "CancellableOrder", variable: "?o" },
    },
  ],
  entity_specs: {
    "Order" => {
      description: "A purchase order. Detectable by mm:order: " \
                   "IRI in context or explicit numeric ID.",
    },
  },
  assertion_specs: {
    "orderAge" => {
      description: "Integer days since order creation. Read from " \
                   "the mm:created_at timestamp.",
    },
  },
  complementary: true,  # opt in to the Sadowski-Chudziak SD-Comp condition
}
```

#### Validation (raises `Vv::Decision::Errors::InvalidTaskOntology`)

- TBox `classes:` is a non-empty Array of CamelCase strings.
- `object_properties:` and `data_properties:` Hash values have
  `domain:` and `range:` keys with class strings.
- `swrl_rules:` is a non-empty Array (an ontology with zero
  rules is non-actionable; the `task_not_rule_governed`
  tripwire would always fire).
- Each rule's `consequent.class` MUST be in `tbox.classes`.
- `entity_specs:` covers at least every class that appears as a
  rule consequent or antecedent.
- `assertion_specs:` covers at least every property that appears
  in a rule.
- Total serialized size ≤ 64 KB (a soft cap; per-task
  ontologies are typically much smaller; operators with bigger
  ontologies split per-scope or factor shared TBox into imports
  — but v0.1.3 does NOT ship ontology imports).
- `complementary:` is a Boolean (default `false`).

#### Methods

- `#tbox` / `#swrl_rules` / `#entity_specs` / `#assertion_specs`
  / `#complementary?` — frozen accessors.
- `#suitable?(:rule_expressible_boundary)` / `#suitable?(:formalisable_predicates)`
  — Booleans from the `suitability:` kwarg.
- `#suitability_rationale` — the operator's stated `rationale:`
  string. Persisted with the Decision; surfaced in the
  inspectable ABox per the paper's "reviewable record" principle.
- `#to_h` — deep-dup for round-tripping through jsonb.
- `#content_iri` — `"urn:vv-decision:ontology:sha256:#{sha256}"`.
  Same content-addressed identity pattern as v0.1.1's
  `EpistemicSchema#content_iri`.
- `#entity_classes` / `#assertion_predicates` — small derived
  helpers for the Phase C flow methods' validation paths.

#### Exit criteria
- Spec: `TaskOntology.from_hash(hash, suitability: ...)` returns a frozen ontology.
- Spec: omitting `suitability:` raises `SuitabilityNotAttested`.
- Spec: a rule with a consequent class NOT in TBox raises `InvalidTaskOntology`.
- Spec: a rule referencing a property NOT in TBox raises `InvalidTaskOntology`.
- Spec: an ontology with empty `swrl_rules:` raises `InvalidTaskOntology`.
- Spec: a 65 KB ontology raises `TaskOntologyTooLarge`.
- Spec: `#content_iri` is the same for two ontologies with semantically identical content (sorted keys, no whitespace).
- Spec: `#suitable?` round-trips the `suitability:` Hash entries.

### Phase B — `deliberate(..., task_ontology:)` + persistence

```ruby
ontology = Vv::Decision::TaskOntology.load_owl_xml(
  File.read("config/cancellation.owl"),
  suitability: { rule_expressible_boundary: true, formalisable_predicates: true,
                 rationale: "..." },
)

decision = Vv::Decision.deliberate(
  scope:            session,
  context:          "user asked: should we cancel order 42?",
  epistemic_schema: schema,           # optional, from v0.1.1
  task_ontology:    ontology,         # optional, new in v0.1.3
) do |ctx|
  ctx.identify_entities!(...)         # Phase C
  ctx.extract_assertions!(...)        # Phase C
  outcome = ctx.apply_rules!(...)     # Phase C
  ctx.decide!(option: outcome.classification, because: outcome.rationale)
end
```

#### Schema migration (additive)

```ruby
class AddStructuredDecompositionToVvDecisionDecisions < ActiveRecord::Migration[8.1]
  def change
    add_column :vv_decision_decisions, :task_ontology,           :jsonb, null: false, default: {}
    add_column :vv_decision_decisions, :populated_abox,          :jsonb, null: false, default: []
    add_column :vv_decision_decisions, :classification_outcome,  :jsonb, null: false, default: {}
  end
end
```

All three columns default to empty. v0.1.0 + v0.1.1 rows
backfill trivially. SQLite uses `:json` per the established
pattern.

#### Implementation

- `Vv::Decision.deliberate(scope:, context:, provenance_id: nil,
  epistemic_schema: nil, task_ontology: nil, &block)`:
  - If `task_ontology:` is non-nil, store `#to_h` into the
    `task_ontology` column.
  - Pass the ontology (or `nil`) into the `DeliberationContext`.
- `DeliberationContext#task_ontology` — reader. Stable handle
  for the Phase C flow methods.
- `Decision#task_ontology` — returns a `TaskOntology` (or `nil`)
  reconstructed from the jsonb column. Memoized.
- `Decision#populated_abox` — raw jsonb array. Each entry:
  `{ "step" => "entity_identification" | "assertion_extraction",
  "individual" => "...", "class" => "...", "value" => ...,
  "justification" => "...", "at" => ISO8601 }`.
- `Decision#classification_outcome` — raw jsonb hash:
  `{ "classification" => "...", "rule_revision" => "...",
  "reasoner_revision" => "...", "decided_at" => ISO8601 }`.

#### Exit criteria
- Spec: `deliberate(...)` without `task_ontology:` persists a Decision with all three new columns empty. Existing v0.1.0/v0.1.1 specs pass unchanged.
- Spec: `deliberate(..., task_ontology: ontology)` persists `ontology.to_h`; `decision.task_ontology == ontology`.
- Spec: `ctx.task_ontology` returns the ontology (or `nil`).
- Spec: `Decision#task_ontology` is memoized and frozen.
- Spec: combined `epistemic_schema: + task_ontology:` call persists both columns independently.

### Phase C — three new flow methods + reasoner adapter

The Sadowski–Chudziak three-step decomposition. Each method
records a Bronze episode and updates the Decision's
`populated_abox` / `classification_outcome` jsonb columns.

The methods are **operator-supplies, gem-records** — same
layering rule as v0.1.0's `reason_with`. The operator invokes
the LLM (or whatever extraction mechanism); the gem records the
extracted entities/assertions/outcome and gates them against the
TBox.

```ruby
# Step 1 — entity identification
entities = ctx.identify_entities!(
  text: "should we cancel order 42, which has dependency on order 17?",
  entities: [
    { individual: "order_42", class: "Order",            justification: "explicit ID in user text" },
    { individual: "order_17", class: "ActiveDependency", justification: "mentioned as dependency" },
  ],
)

# Step 2 — assertion extraction
assertions = ctx.extract_assertions!(
  entities: entities,
  assertions: [
    { individual: "order_42", property: "orderAge",      value: 31,            justification: "created 2026-04-25" },
    { individual: "order_42", property: "paymentStatus", value: "refundable",  justification: "mm:status read" },
    { individual: "order_42", property: "hasDependency", value: "order_17",    justification: "mm:has_dependency triple" },
  ],
)

# Step 3 — rule application (symbolic reasoner)
outcome = ctx.apply_rules!(
  suitability_attestation: "Order cancellation eligibility is rule-governed per MM cancellation policy",
)
# outcome.classification == "CancellableOrder" (or nil if no rule fired)
# outcome.rationale       == "Rule fired: orderAge>30 ∧ paymentStatus=refundable → CancellableOrder"
```

#### Reasoner adapter interface

```ruby
class Vv::Decision::Reasoner
  # @param ontology  [Vv::Decision::TaskOntology]
  # @param abox      [Array<Hash>] — the populated_abox entries
  # @return          [Vv::Decision::ClassificationOutcome]
  def apply!(ontology:, abox:)
    raise NotImplementedError
  end

  def revision
    raise NotImplementedError
  end
end
```

v0.1.3 ships **two** reasoner classes:

- `Vv::Decision::Reasoner::Null` — the default. Always returns
  the operator-supplied classification (passed as a kwarg to
  `apply_rules!`). The operator owns the reasoning; the gem
  just records the trace. This preserves v0.1.0's "operator
  invokes, gem records" lane.
- `Vv::Decision::Reasoner::SwrlMatcher` — a **conjunctive
  forward-chainer** over the populated ABox + the TaskOntology's
  SWRL rules. Handles the conjunctive-antecedent rule shape
  used by all three of the paper's case studies (hearsay,
  method application, eligibility). Does NOT handle full OWL 2
  reasoning, class-hierarchy subsumption, or open-world
  inference — those require Pellet / HermiT / FaCT++, which
  this gem does not ship. The matcher's
  `Vv::Decision::Errors::ReasonerOutOfDepth` signals when a
  rule requires reasoning beyond the matcher's depth.

Operators with full-reasoner needs register their own:
`Vv::Decision::Reasoner.register(MyPelletAdapter.new)`. The
adapter's `revision` string lands in the
`classification_outcome` column for audit.

#### Implementation details

- `#identify_entities!(text:, entities:)` — gates each entity's
  `class:` against `ontology.entity_classes`; refuses with
  `Errors::InvalidEntityClass` for unknown classes. Records a
  Bronze `decision_entity_identification` episode with
  `{ text: "...", entities: [...] }`. Appends each entity to
  `decision.populated_abox` with `step: "entity_identification"`.
- `#extract_assertions!(entities:, assertions:)` — gates each
  assertion's `property:` against `ontology.assertion_predicates`;
  refuses with `Errors::InvalidAssertionPredicate`. Records a
  Bronze `decision_assertion_extraction` episode. Appends each
  assertion to `populated_abox` with
  `step: "assertion_extraction"`.
- `#apply_rules!(suitability_attestation:, reasoner: Reasoner::SwrlMatcher.new)` —
  the `suitability_attestation:` kwarg is required; absent it,
  the `task_not_rule_governed` tripwire fires (Phase E). The
  reasoner's `#apply!` is called with the populated ABox + the
  ontology; the returned `ClassificationOutcome` is written to
  `decision.classification_outcome`. Records a Bronze
  `decision_rule_application` episode with the reasoner's
  revision string.
- `Vv::Decision::ClassificationOutcome` — frozen Struct:
  `classification:` (String or nil), `rationale:` (String),
  `rule_revision:` (the IRI of the SWRL rule that fired, or
  `"none"`), `reasoner_revision:` (the adapter's revision
  string), `decided_at:` (Time).

#### Composability with v0.1.0's flow methods

The three new methods compose with the existing five:

- `ctx.recall(...)` may run before entity identification to
  ground the entities in Silver-side evidence.
- `ctx.consider(...)` may still be called to record rejected
  alternatives even when a rule fires.
- `ctx.reason_with(...)` may still be called to record an
  end-to-end model call (e.g., a sanity-check LLM call against
  the rule's outcome).
- `ctx.decide!(...)` is still the commit point. Operators
  typically pass `option: outcome.classification.to_sym` and
  `because: outcome.rationale`.

#### Exit criteria
- Spec: `ctx.identify_entities!` with an entity whose `class:` is not in the ontology raises `InvalidEntityClass`.
- Spec: `ctx.extract_assertions!` with a property not in the ontology raises `InvalidAssertionPredicate`.
- Spec: `ctx.apply_rules!` without `suitability_attestation:` fires the `task_not_rule_governed` tripwire (Phase E).
- Spec: `Reasoner::Null#apply!` returns the kwarg-supplied classification.
- Spec: `Reasoner::SwrlMatcher#apply!` correctly fires a conjunctive antecedent rule against a populated ABox.
- Spec: `Reasoner::SwrlMatcher#apply!` returns `classification: nil` when no rule's antecedent is satisfied.
- Spec: `Reasoner::SwrlMatcher` raises `ReasonerOutOfDepth` on rules requiring open-world inference (a rule referencing class subsumption with no explicit assertion).
- Spec: a full three-step pass populates `decision.populated_abox` with the entity + assertion entries in order.
- Spec: a full three-step pass writes `decision.classification_outcome` with the reasoner's outcome.
- Spec: the existing `reason_with(...)` still works when called alongside the three new methods.

### Phase D — `DecisionExtractor` revision bump + new `vvdec:` predicates

The `DecisionExtractor` revision bumps from v0.1.1's value to
the v0.1.3 value (per CONSUMER_REQUIREMENT_DS.md B2's
convention reconciliation: `"decision-v3"`). Triggers
cursor-replay so existing v0.1.0–v0.1.1 decisions backfill the
new (zero-content) predicates.

#### New predicates

```turtle
@prefix vvdec: <urn:vv-decision:annotation:> .

<urn:vv-decision:decision:42>
    vvdec:applies_ontology    <urn:vv-decision:ontology:sha256:def456…> ;
    vvdec:populated_individual <urn:vv-decision:individual:42:order_42> ;
    vvdec:populated_individual <urn:vv-decision:individual:42:order_17> ;
    vvdec:asserted_property   <urn:vv-decision:assertion:42:1> ;
    vvdec:asserted_property   <urn:vv-decision:assertion:42:2> ;
    vvdec:reasoner_classified "CancellableOrder" ;
    vvdec:complementary_predicate_used "false"^^xsd:boolean .

<urn:vv-decision:individual:42:order_42>
    rdf:type                <urn:vv-decision:annotation:OntologyClass:Order> ;
    vvdec:individual_text   "order 42" ;
    vvdec:individual_just   "explicit ID in user text" .

<urn:vv-decision:assertion:42:1>
    vvdec:assertion_subject   <urn:vv-decision:individual:42:order_42> ;
    vvdec:assertion_predicate "orderAge" ;
    vvdec:assertion_value     "31"^^xsd:integer ;
    vvdec:assertion_just      "created 2026-04-25" .
```

The `vvdec:applies_ontology` IRI is content-addressed via
`TaskOntology#content_iri` — two decisions sharing the same
ontology share the same `applies_ontology` subject. Operators
querying "which decisions applied this ontology" do a single
SPARQL lookup. The `OntologyClass:Order` IRI shape composes the
ontology's namespace with the class name — operators querying
"all `Order` individuals across this scope's Decisions"
likewise.

#### Implementation

- `DecisionExtractor#revision` → `"decision-v3"`.
- The v0.1.1 emit list is unchanged. New triples are emitted
  when:
  - `task_ontology` jsonb column is non-empty → emit
    `vvdec:applies_ontology` + the `vvdec:complementary_predicate_used` flag.
  - `populated_abox` jsonb column is non-empty → emit one
    `vvdec:populated_individual` per entity entry + one
    `vvdec:asserted_property` per assertion entry. Each
    individual/assertion gets a subordinate set of scalar
    triples (text, justification, etc.).
  - `classification_outcome` jsonb column is non-empty → emit
    one `vvdec:reasoner_classified` literal triple.
- Reuses `Vv::Decision::Vocabulary::VVDEC` from work unit 3.
- The shim path (`Vv::Decision::DecisionExtractor::V0_1_1` —
  a marker class) lets operators pin the v0.1.1 revision and
  avoid the re-emit cost. Same shim shape as the v0.1.0 / v0.1.1
  shim from PLAN_0_1_1 §Risks row 4.

#### Exit criteria
- Spec: a `deliberate(...)` with no `task_ontology:` → after `conform_now!`, none of the five new predicates appear. Silver is byte-identical to v0.1.1.
- Spec: a `deliberate(...)` with an ontology and a full three-step pass → `vvdec:applies_ontology` lands once, `vvdec:populated_individual` lands once per entity, `vvdec:asserted_property` lands once per assertion, `vvdec:reasoner_classified` lands once.
- Spec: two decisions sharing the same ontology have the same `vvdec:applies_ontology` IRI.
- Spec: the `vvdec:complementary_predicate_used` triple reflects `ontology.complementary?`.
- Spec: bumping the extractor revision re-emits the new predicates for v0.1.0–v0.1.1-era decisions (cursor-replay path, verified per CONSUMER_REQUIREMENT_DS.md B6).

### Phase E — `task_not_rule_governed` tripwire integration

Composes with v0.1.1's TripwireInterpreter. Adds one new
built-in pattern and one new firing stage.

#### New pattern

| Pattern | Stage | What it matches |
|---|---|---|
| `task_not_rule_governed` | `apply_rules` | Fires if (a) `task_ontology` is `nil` while `ctx.apply_rules!` is called, OR (b) `suitability_attestation:` is `nil` or blank, OR (c) `ontology.swrl_rules` is empty, OR (d) every SWRL rule has a consequent class NOT in the deliberation's expected target classes (configurable via the schema's `target_classes:` field). |

The action defaults to `:refuse_and_flag` (the operator must
opt into a softer action if they want the pass to continue
with a non-rule-governed task — this is the URTI safety net).

#### Implementation

- New firing stage `"apply_rules"` added to the
  `Vv::Decision::EpistemicSchema` validator's accepted
  `fires_on:` enum.
- `Vv::Decision::TripwireInterpreter.check_apply_rules!(ctx:,
  ontology:, suitability_attestation:)` — checks the four (a–d)
  conditions; returns matched entries.
- The check fires **before** the reasoner is invoked — if the
  task is not rule-governed, we want to refuse to apply rules
  in the first place, not refuse after the (incorrect) outcome
  is computed.
- An operator who explicitly wants to record a non-rule-governed
  task's "rule-application" attempt (for negative-result audit)
  passes a schema with `task_not_rule_governed` action set to
  `:flag`, which records but does not raise. The reasoner then
  returns a `classification: nil` outcome and the operator's
  `decide!` proceeds normally.

#### Exit criteria
- Spec: `ctx.apply_rules!(suitability_attestation: nil)` with a schema-less ontology fires the tripwire with the default `:refuse_and_flag` action; raises `TripwireFired`.
- Spec: with a schema that softens to `:flag`, the same call records but does not raise; returns a `classification: nil` outcome.
- Spec: an ontology with zero SWRL rules fires the tripwire even with `suitability_attestation:` present.
- Spec: an ontology that fails the target-class check (no rule consequent in `schema.target_classes`) fires the tripwire.
- Spec: a deliberation with both `epistemic_schema:` and `task_ontology:` runs all schema tripwires AND the `task_not_rule_governed` tripwire — they fire independently.

### Phase F — `bin/check`, docs, CHANGELOG → tag 0.1.3

- `bin/check` — unchanged binary; new specs run under the existing harness.
- `CHANGELOG.md` — `0.1.3 — (unreleased)` heading with the per-phase entries.
- `README.md` — add a "Structured decomposition" section above the "Epistemic schemas" section from v0.1.1. Include:
  - The three-step decomposition example (entity identification → assertion extraction → rule application).
  - The suitability criteria with the URTI counter-example as a refusal-to-apply rule.
  - A worked example end-to-end (the order-cancellation case used in this PLAN).
  - Cross-reference to `docs/research/StructuredDecomp.md`.
- `CONSUMER_REQUIREMENT_MM.md` — extend with the three new reserved `kind:` strings: `"decision_entity_identification"`, `"decision_assertion_extraction"`, `"decision_rule_application"`.
- `VERSION` → `0.1.3`.
- `lib/vv/decision/version.rb` → `VERSION = "0.1.3"`.

#### Exit criteria
- `bin/check` exits 0.
- The full v0.1.0 + v0.1.1 spec suite passes unchanged (additivity proof).
- A new `structured_decomposition_integration_spec.rb` passes: full round-trip — ontology load → `deliberate` with ontology → three-step decomposition → reasoner classifies → schema persisted → re-read via `Decision#task_ontology` → `conform_now!` → new vvdec: predicates land in Silver.
- A negative-path spec: a non-rule-governed task (the URTI shape) fires `task_not_rule_governed` at `apply_rules!` time; the deliberation rolls back.
- `CHANGELOG.md` `0.1.3` heading drops `(unreleased)`.

## Out of scope for v0.1.3

- **Full OWL 2 reasoner integration.** The paper uses Pellet via
  owlready2 (Python). The Ruby ecosystem lacks a battle-tested
  full-OWL reasoner. v0.1.3 ships `Reasoner::SwrlMatcher` which
  handles conjunctive-antecedent forward-chaining only; richer
  reasoning (class subsumption, property inheritance, open-world
  inference, SWRL built-ins beyond equality/inequality) require
  an adapter the operator registers themselves. Tracked for
  v0.2.0+: a `vv-reasoner` sibling gem or an HTTP-adapter to an
  external OWL reasoner service.
- **Ontology imports.** Each ontology is self-contained. The
  W3C `owl:imports` mechanism for composable TBox is not
  supported in v0.1.3 — operators duplicate shared TBox across
  ontologies. Deferred to v0.2.0+ once a consumer asks.
- **LLM-driven entity / assertion extraction.** The gem does
  NOT invoke the LLM. The three new flow methods accept
  operator-supplied entities/assertions; the operator decides
  how to extract them (most operators will use an LLM, but
  vv-decision is neutral on the choice — same as `reason_with`
  in v0.1.0). A future v0.2.0+ may ship a
  `Vv::Decision::Extractor` adapter interface that wraps an LLM
  call against the TBox-defined entity_specs; v0.1.3 does not.
- **Complementary-predicates emission helper.** The paper's
  SD-Comp condition pairs each predicate with its negation
  (`FunctionalConn` ↔ `NoFunctionalConn`, etc.) to mitigate
  confirmation bias under OWA. v0.1.3 ships the `complementary?`
  Boolean and records it in Silver, but does NOT auto-generate
  the paired predicates. Operators authoring an ontology with
  `complementary: true` are responsible for declaring both
  members of each predicate pair. A v0.2.0+ helper
  (`TaskOntology.with_complementary_predicates`) may auto-pair.
- **Suitability auto-detection.** No automatable test for "is
  this task rule-governed." The `suitability:` kwarg requires
  operator attestation; the `task_not_rule_governed` tripwire
  catches obvious failures (empty rules, missing attestation)
  but cannot detect the URTI shape where the predicates ARE
  formalisable but the boundary IS statistical. Operators own
  the suitability call.
- **Multi-ontology composition.** A deliberation carries at
  most one `task_ontology:`. Tasks spanning multiple ontologies
  decompose into multiple deliberations.
- **Other v0.1.0 / v0.1.1 deferrals.** All v0.2.0+ items from
  PLAN_0_1_0 / PLAN_0_1_1 (analytical facades, causal
  traversal, action emission, Curator integration,
  `Vv::Memory.recall(...)` facade integration, schema
  inheritance, SHACL integration, schema generation) remain
  out of scope.

## v0.1.3 contract additions (frozen at release)

| Surface | Shape | Mutability |
|---|---|---|
| `Vv::Decision.deliberate(scope:, context:, provenance_id: nil, epistemic_schema: nil, task_ontology: nil, &block)` | module method — adds the `task_ontology:` kwarg | **Additive on v0.1.1.** Kwarg defaults to `nil`; v0.1.0 + v0.1.1 call shapes resolve unchanged. |
| `Vv::Decision::TaskOntology.load_owl_xml` / `.load_turtle` / `.from_hash` | class methods | **Pinned.** All require `suitability:` kwarg. |
| `Vv::Decision::TaskOntology#tbox` / `#swrl_rules` / `#entity_specs` / `#assertion_specs` / `#complementary?` / `#suitable?` / `#suitability_rationale` / `#to_h` / `#content_iri` / `#entity_classes` / `#assertion_predicates` | instance methods | **Pinned.** |
| `Vv::Decision::DeliberationContext#task_ontology` / `#identify_entities!` / `#extract_assertions!` / `#apply_rules!` | instance methods | **Pinned.** Method names + kwargs pinned for v0.1.x; semantics may tighten additively. |
| `Vv::Decision::Decision#task_ontology` / `#populated_abox` / `#classification_outcome` | instance methods on the AR row | **Pinned.** `#task_ontology` returns `nil` for v0.1.0–v0.1.1-era rows (empty jsonb). |
| `task_ontology` + `populated_abox` + `classification_outcome` jsonb columns | schema | **Pinned column names.** Defaults `{}`, `[]`, `{}`. |
| `Vv::Decision::ClassificationOutcome` Struct: `classification:` / `rationale:` / `rule_revision:` / `reasoner_revision:` / `decided_at:` | value object | **Pinned field names.** |
| `Vv::Decision::Reasoner` base class with `#apply!(ontology:, abox:)` + `#revision` | extension point | **Pinned signature.** Custom adapters subclass and `register`. |
| `Vv::Decision::Reasoner::Null` / `Vv::Decision::Reasoner::SwrlMatcher` | shipped classes | **Pinned class names.** `SwrlMatcher`'s rule-firing behavior is pinned at the conjunctive-antecedent shape; additive new SWRL features in v0.1.x preserve every previously-firing case. |
| Bronze episode `kind:` strings: `"decision_entity_identification"` / `"decision_assertion_extraction"` / `"decision_rule_application"` | conventions | **Pinned.** Added to `Vv::Decision::EPISODE_KINDS`. |
| Tripwire pattern `"task_not_rule_governed"`; tripwire stage `"apply_rules"` | conventions | **Pinned strings.** The pattern's heuristic implementation may tighten additively in v0.1.x. |
| `vvdec:applies_ontology` / `vvdec:populated_individual` / `vvdec:asserted_property` / `vvdec:reasoner_classified` / `vvdec:complementary_predicate_used` (+ subordinate scalars on individual/assertion subjects) | RDF predicates | **Pinned IRIs.** |
| `urn:vv-decision:ontology:sha256:<hex>` IRI scheme for `vvdec:applies_ontology` subjects | convention | **Pinned.** |
| `urn:vv-decision:individual:<decision_id>:<individual_name>` and `urn:vv-decision:assertion:<decision_id>:<n>` IRI schemes | conventions | **Pinned.** |
| `Vv::Decision::Errors::InvalidTaskOntology` / `TaskOntologyTooLarge` / `SuitabilityNotAttested` / `InvalidEntityClass` / `InvalidAssertionPredicate` / `ReasonerOutOfDepth` | exception classes | **Pinned class names.** |
| `DecisionExtractor#revision` = `"decision-v3"` (or the equivalent post-B2-resolution string) | string | **Bumped from v0.1.1.** Triggers cursor-replay; existing decisions backfill the new (zero-content) predicates. |

The pinned v0.1.0 + v0.1.1 surfaces are unchanged. Every prior
contract row still holds at v0.1.3.

## Risks

| Risk | Mitigation |
|---|---|
| Operators apply structured decomposition to non-rule-governed tasks (the URTI shape) and see catastrophic F1 regressions (the paper's 0.145 vs 0.979 finding). | The Phase A `suitability:` kwarg + the Phase E `task_not_rule_governed` tripwire are the two-layer safety net. The README's Quickstart documents the URTI counter-example as a refusal-to-apply rule. The `Reasoner::SwrlMatcher` will return `classification: nil` when no rule fires (which is the right behavior for an ill-suited task), surfacing the misapplication rather than producing a confident-but-wrong outcome. |
| The shipped `Reasoner::SwrlMatcher` is conjunctive-only and operators with class-hierarchy reasoning needs hit `ReasonerOutOfDepth`. | Documented limitation. The adapter interface (`Vv::Decision::Reasoner` base class) gives operators an escape hatch — register a full-reasoner adapter (Pellet via JRuby, HermiT via shell, an HTTP service, etc.). v0.2.0+ may ship a `vv-reasoner` sibling gem; v0.1.3 ships the seam. |
| The TaskOntology's jsonb column carries the full TBox + SWRL rules + entity/assertion specs, which can grow large for complex domains. The 64 KB cap is generous but operators with dozens of classes may exceed it. | Operators with large ontologies factor shared TBox into separate domain-vocabulary files (referenced by string identifier in the per-decision ontology) and use the `content_iri` lookup to deduplicate at the Silver layer. Ontology imports (which would solve this cleanly) are deferred to v0.2.0+ — tracked in "Out of scope". |
| The three new flow methods + the existing five methods produce ergonomic confusion. Operators may not know whether to call `reason_with` or the three-step decomposition. | The README's "How to choose" section answers: if the task is rule-governed AND the predicates are formalisable, use the three-step decomposition; otherwise use `reason_with`. Both are valid; both record provenance. The choice is per-deliberation, not per-scope. |
| The complementary-predicates pattern (Sadowski–Chudziak SD-Comp) requires the operator to author *paired* predicates. Operators who set `complementary: true` but forget half the pairs get the bias-mitigation benefit only for the pairs they actually authored. | Phase A's validation warns (not raises) when fewer than two assertion_specs share a stem (e.g., `FunctionalConn` without `NoFunctionalConn`). The warning lands as a `Vv::Decision::Warnings::IncompleteComplementaryPair` (a new lightweight warning class) — not blocking, but visible in `decision.warnings`. |
| The DecisionExtractor revision bump re-emits triples for every existing decision; for substrates with many decisions, this is expensive. | Same mitigation as v0.1.1: the `Vv::Decision::DecisionExtractor::V0_1_1` shim lets operators pin the older revision until ready. The shim shape is pinned at v0.1.3 alongside the v0.1.0 / v0.1.1 ones. |
| The `Reasoner::SwrlMatcher` re-implements forward-chaining; if the implementation has a subtle bug, every operator using the default reasoner shares the bug. | The matcher is small (~150 LOC budget) and its rule-firing behavior is exercised by a fuzz-style spec drawing rules + ABoxes from the three case studies in the paper (hearsay, method application, eligibility). The spec is pinned to the paper's expected outcomes; a regression breaks the build, not silently. |
| Operators query the Silver tier with SPARQL that joins `vvdec:populated_individual` across many decisions and the cardinality explodes (each decision may have ~5–20 individuals). | Documented. The `vvdec:applies_ontology` content-addressed IRI is the recommended join key when querying "all decisions using this ontology"; the per-decision individuals are the second-level traversal. v0.2.0+'s class-level analytical facades will package this pattern. |
| The new `apply_rules` tripwire stage breaks v0.1.1 epistemic schemas that didn't anticipate it — schemas using `fires_on:` validation in unexpected ways. | The Phase A validator (in `EpistemicSchema.load_yaml`) accepts the new `apply_rules` stage additively; existing schemas with only `recall` / `reason_with` / `decide` / `consider` stages continue to validate. No v0.1.1 schema rejected post-v0.1.3. |
| Operator-supplied entities/assertions don't actually correspond to LLM output; the operator hand-codes them. The audit-trail value of the populated ABox depends on the entities/assertions being grounded in text. | Same operator-responsibility rule as v0.1.0's `reason_with`. The gem records what the operator passes; the operator owns the grounding. The `justification:` field on each entity/assertion is pinned in v0.1.3 specifically so operators record the text-grounding even when the LLM-call is implicit. README's Quickstart shows the recommended pattern. |
| Transaction wrapping in `deliberate(...)` means a slow LLM call inside `ctx.identify_entities!` (which is operator-side, but the transaction is open) holds the DB transaction open. | Same v0.1.0 design constraint: v0.1.3 does NOT invoke the LLM. The operator extracts entities outside the transaction OR accepts that their LLM call holds the transaction. v0.2.0+'s two-transaction pattern (open → extract → reopen → commit) addresses this. Tracked. |

## Acceptance signal

1. Phases A/B/C/D/E/F land with passing specs; the new
   `structured_decomposition_integration_spec.rb` is green;
   the negative-path URTI-shape spec is green (the deliberation
   rolls back as expected).
2. The full v0.1.0 + v0.1.1 spec suites pass unchanged
   (additive proof — no v0.1.0 or v0.1.1 spec is touched).
3. `bin/check` green against the canonical dev environment.
4. `CHANGELOG.md` `0.1.3` heading drops `(unreleased)`.
5. `VERSION` → `0.1.3`.
6. `README.md` documents the `TaskOntology` value object, the
   three-step decomposition, the suitability criteria with the
   URTI counter-example, and the `Reasoner::SwrlMatcher`
   default with its conjunctive-antecedent limitation.
7. `CONSUMER_REQUIREMENT_MM.md` notes the three new reserved
   `kind:` strings.
8. At least one `mm-server` agent path carries a real
   `task_ontology:` argument against the tagged 0.1.3 — proves
   the surface is usable end-to-end. (Tracked as the 0.1.4 /
   first-consumer-PR milestone if not landed concurrently with
   the tag.)
9. The three-domain replication spec (a smoke test that
   re-implements the paper's hearsay, method-application, and
   clinical-trial-eligibility ontologies at minimal scope and
   exercises the full three-step flow against operator-supplied
   entities/assertions matching the paper's positive + negative
   examples) is green. This is the cross-domain
   generalisability proof at the gem level — not a re-run of
   the paper's 33-model evaluation, but a demonstration that
   the gem's surface accommodates all three case-study shapes.

## Cross-references

- `../../../../docs/research/StructuredDecomp.md` — the paper
  motivating this release. Authoritative on the three-step
  decomposition, the suitability criteria, the
  complementary-predicates pattern, and the URTI counter-example.
- `../../../../docs/research/DecisionContext.md` — v0.1.1's
  motivating research. Structured decomposition composes with
  epistemic schemas; both surfaces coexist on a single
  `deliberate(...)` call.
- `../../../../docs/research/DecisionLayer.md` — the original
  architectural finding for the gem.
- `./PLAN_0_1_0.md` — the v0.1.0 design baseline. Every contract
  row still holds at v0.1.3.
- `./PLAN_0_1_1.md` — the v0.1.1 design baseline. The
  TripwireInterpreter from §Phase C is extended in §Phase E
  of this plan.
- `./PLAN_0_1_2.md` — the implementation plan. Work units
  12–17 (extending 1–11) execute this PLAN; gate G4 verifies
  the reasoner-adapter integration assumption before work unit
  14 begins.
- `../../../vv-memory/CONSUMER_REQUIREMENT_DS.md` — DS's
  perspective on vv-memory. B2 (revision-string convention)
  determines the new revision string at Phase D; B6
  (cursor-replay idempotency) is exercised at Phase D's
  re-emission path.
- `../../README.md` — this gem's README (gets a "Structured
  decomposition" section in Phase F).
