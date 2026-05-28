# frozen_string_literal: true

require "spec_helper"

# PLAN_0_1_0 Phase F — the v0.1.0 acceptance signal in one test.
#
# Full happy path: deliberate (all flow methods) → five-kind Bronze
# → conform_now! → vvdec: Silver triples + vvmem: provenance →
# read-side traversal → checkpoint → evict → hydrate → triples
# survive the Active Storage round-trip.
RSpec.describe "Vv::Decision end-to-end", :requires_extension do
  let(:session_class) do
    Class.new(::ActiveRecord::Base) do
      self.table_name = "sessions"
      include ::Vv::Memory::Scoped
      def self.name; "FakeSession"; end
    end.tap do |klass|
      klass.vv_memory do
        silver_iri    -> { "urn:vv-memory:session:#{id}:silver" }
        checkpoint_on :explicit
      end
    end
  end

  before(:each) do
    stub_const("FakeSession", session_class)
    Vv::Decision.register_extractor!
  end

  let(:session) { session_class.create!(name: "S1") }
  let(:iri)     { "urn:vv-memory:session:#{session.id}:silver" }

  it "round-trips deliberate → conform → recall → checkpoint/evict/hydrate" do
    session.memory_silver[:hydrate!].call

    # 2. Seed Silver with order triples for recall to find.
    # raw bulk_insert expects bare IRIs (no angle brackets) in the
    # object column; literals stay quoted.
    ::Vv::Graph::Sparql.bulk_insert([
      ["urn:mm:order:42", "mm:status",         '"open"',         iri],
      ["urn:mm:order:42", "mm:has_dependency", "urn:mm:order:17", iri],
    ], raw: true)

    # 3. Deliberate — exercise all four flow methods + decide!.
    decision = Vv::Decision.deliberate(scope: session, context: "cancel order 42?") do |ctx|
      evidence = ctx.recall(query: "SELECT ?s ?p ?o WHERE { ?s ?p ?o }")
      ctx.consider(option: :cancel, grounded_in: evidence.where(predicate: "mm:status"))
      ctx.consider(option: :hold,   grounded_in: evidence.where(predicate: "mm:has_dependency"))
      ctx.reason_with(model: :claude_opus_4_7, prompt: "which?", completion: "hold")
      ctx.decide!(option: :hold, because: "active dependency on order 17 unresolved")
    end

    # 4. Persisted + decided.
    expect(decision).to be_persisted
    expect(decision.decided?).to be(true)

    # 5. The five-kind Bronze flow landed.
    kinds = session.memory_episodes.pluck(:kind).tally
    expect(kinds["decision_context"]).to eq(1)
    expect(kinds["decision_query"]).to eq(1)
    expect(kinds["decision_consider"]).to eq(2)
    expect(kinds["decision_reasoning"]).to eq(1)
    expect(kinds["decision_outcome"]).to eq(1)

    # 6. Conform Bronze → Silver.
    session.conform_now!

    subj = "urn:vv-decision:decision:#{decision.id}"
    ask = ->(pat) { ::Vv::Graph::Sparql.ask("ASK { #{pat} }", graph: iri)[:value] }

    # 7. vvdec: headline + content triples.
    expect(ask.call("<#{subj}> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:vv-decision:annotation:Decision>")).to be(true)
    expect(ask.call(%(<#{subj}> <urn:vv-decision:annotation:decided_option> "hold"))).to be(true)
    # EvidenceSlice#iris yields the subject IRIs of the matched rows
    # (order:42), which is what `consider(grounded_in:)` stores.
    expect(ask.call("<#{subj}> <urn:vv-decision:annotation:grounded_in> <urn:mm:order:42>")).to be(true)

    # 8. Parent Conformer vvmem: provenance on the quoted-triple subject.
    quoted = "<< <#{subj}> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:vv-decision:annotation:Decision> >>"
    expect(ask.call(%(#{quoted} <urn:vv-memory:annotation:extractedBy> "vv-decision/v0.1.0/DecisionExtractor"))).to be(true)

    # 9. Read-side methods return expected shapes.
    expect(decision.alternatives_considered.map { |a| a["option"] }).to eq(["cancel"])
    expect(decision.evidence_slice).to be_a(Vv::Decision::EvidenceSlice)
    expect(decision.reasoning_trace[:model]).to eq("claude_opus_4_7")
    expect(decision.impact).to be_a(::ActiveRecord::Relation)

    # 10. Checkpoint → evict → hydrate; vvdec: triples survive.
    before_size = ::Vv::Graph::Sparql.store_size(graph: iri)[:count]
    expect(session.memory_silver[:checkpoint!].call).to include(ok: true)
    ::Vv::Graph::Sparql.execute("CLEAR ALL")
    session.memory_silver[:evict!].call
    expect(::Vv::Graph::Sparql.store_size(graph: iri)[:count]).to eq(0)

    session.reload
    expect(session.memory_silver[:hydrate!].call).to include(ok: true)
    expect(::Vv::Graph::Sparql.store_size(graph: iri)[:count]).to eq(before_size)
    expect(ask.call("<#{subj}> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:vv-decision:annotation:Decision>")).to be(true)
  end
end
