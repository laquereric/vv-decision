# frozen_string_literal: true

require "spec_helper"

# PLAN_0_1_0 Phase D — DecisionExtractor (Conformer subclass) +
# registry registration. Exercises the full Bronze → Silver path.
RSpec.describe Vv::Decision::DecisionExtractor, :requires_extension do
  let(:session_class) do
    Class.new(::ActiveRecord::Base) do
      self.table_name = "sessions"
      include ::Vv::Memory::Scoped
      def self.name; "FakeSession"; end
    end.tap do |klass|
      klass.vv_memory do
        silver_iri -> { "urn:vv-memory:session:#{id}:silver" }
      end
    end
  end

  before(:each) do
    stub_const("FakeSession", session_class)
    Vv::Decision.register_extractor!
  end

  let(:session) { session_class.create!(name: "S1") }
  let(:iri)     { "urn:vv-memory:session:#{session.id}:silver" }
  before(:each) { session.memory_silver[:hydrate!].call }

  def make_decision!
    Vv::Decision.deliberate(scope: session, context: "cancel order 42?") do |ctx|
      ctx.consider(option: :cancel,  grounded_in: ["urn:mm:order:42"])
      ctx.consider(option: :hold,    grounded_in: ["urn:mm:order:17"])
      ctx.consider(option: :proceed, grounded_in: [])
      ctx.reason_with(model: :claude_opus_4_7, prompt: "which?", completion: "hold")
      ctx.decide!(option: :hold, because: "dep on order 17 unresolved")
    end
  end

  def ask(pattern)
    ::Vv::Graph::Sparql.ask("ASK { #{pattern} }", graph: iri)[:value]
  end

  describe "registration" do
    it "routes decision_outcome episodes to DecisionExtractor" do
      expect(Vv::Memory::Conformer::StrategySelector.registered_for("decision_outcome"))
        .to eq(described_class)
      expect(Vv::Memory.conformer_dispatches_by_kind?).to be(true)
    end
  end

  describe "extraction via conform_now!" do
    let!(:decision) { make_decision! }

    before(:each) { session.conform_now! }

    let(:subj) { "urn:vv-decision:decision:#{decision.id}" }

    it "emits the headline rdf:type vvdec:Decision triple" do
      expect(ask("<#{subj}> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:vv-decision:annotation:Decision>")).to be(true)
    end

    it "emits the scalar content predicates" do
      expect(ask(%(<#{subj}> <urn:vv-decision:annotation:context> "cancel order 42?"))).to be(true)
      expect(ask(%(<#{subj}> <urn:vv-decision:annotation:decided_option> "hold"))).to be(true)
      expect(ask(%(<#{subj}> <urn:vv-decision:annotation:because> "dep on order 17 unresolved"))).to be(true)
      expect(ask(%(<#{subj}> <urn:vv-decision:annotation:reasoned_with> "claude_opus_4_7"))).to be(true)
    end

    it "emits grounded_in triples for each evidence IRI" do
      expect(ask("<#{subj}> <urn:vv-decision:annotation:grounded_in> <urn:mm:order:42>")).to be(true)
      expect(ask("<#{subj}> <urn:vv-decision:annotation:grounded_in> <urn:mm:order:17>")).to be(true)
    end

    it "emits alternative_to for rejected options but NOT the chosen one" do
      expect(ask(%(<#{subj}> <urn:vv-decision:annotation:alternative_to> "cancel"))).to be(true)
      expect(ask(%(<#{subj}> <urn:vv-decision:annotation:alternative_to> "proceed"))).to be(true)
      expect(ask(%(<#{subj}> <urn:vv-decision:annotation:alternative_to> "hold"))).to be(false)
    end

    it "lands the parent Conformer vvmem: provenance annotations on the quoted-triple subject" do
      quoted = "<< <#{subj}> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <urn:vv-decision:annotation:Decision> >>"
      expect(ask("#{quoted} <urn:vv-memory:annotation:extractedBy> \"vv-decision/v0.1.0/DecisionExtractor\"")).to be(true)
    end

    it "is idempotent on re-run (no duplicate parent triples)" do
      before_rows = ::Vv::Graph::Sparql.select(
        "SELECT ?p ?o WHERE { <#{subj}> ?p ?o }", graph: iri,
      )[:results].length
      session.conform_now!
      after_rows = ::Vv::Graph::Sparql.select(
        "SELECT ?p ?o WHERE { <#{subj}> ?p ?o }", graph: iri,
      )[:results].length
      expect(after_rows).to eq(before_rows)
    end
  end

  describe "extractor guards" do
    it "returns [] for an undecided decision's (nonexistent) outcome episode" do
      ep = ::Vv::Memory::Episode.create!(scope: session, kind: "decision_outcome", occurred_at: Time.now)
      expect(described_class.new.extract(ep, context: nil)).to eq([])
    end

    it "applies_to? only decision_outcome" do
      ext = described_class.new
      expect(ext.applies_to?(double(kind: "decision_outcome"))).to be(true)
      expect(ext.applies_to?(double(kind: "user_turn"))).to be(false)
    end
  end
end
