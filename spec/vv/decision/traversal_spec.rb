# frozen_string_literal: true

require "spec_helper"

# PLAN_0_1_0 Phase E — read-side aggregate traversal methods.
RSpec.describe "Vv::Decision::Decision read-side traversal", :requires_extension do
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

  before(:each) { stub_const("FakeSession", session_class) }

  let(:session) { session_class.create!(name: "S1") }
  let(:iri)     { "urn:vv-memory:session:#{session.id}:silver" }
  before(:each) { session.memory_silver[:hydrate!].call }

  describe "#trace_back" do
    it "returns prior same-scope decisions whose outcome predates this context, excluding other scopes" do
      earlier = Vv::Decision.deliberate(scope: session, context: "first") do |ctx|
        ctx.decide!(option: :a, because: "x")
      end
      later = Vv::Decision.deliberate(scope: session, context: "second") do |ctx|
        ctx.decide!(option: :b, because: "y")
      end

      other_session = session_class.create!(name: "S2")
      other_session.memory_silver[:hydrate!].call
      Vv::Decision.deliberate(scope: other_session, context: "elsewhere") do |ctx|
        ctx.decide!(option: :c, because: "z")
      end

      expect(later.trace_back.map(&:id)).to eq([earlier.id])
      expect(earlier.trace_back).to eq([])
    end
  end

  describe "#impact" do
    it "returns same-scope episodes after decided_at as a Relation" do
      decision = Vv::Decision.deliberate(scope: session, context: "x") do |ctx|
        ctx.decide!(option: :a, because: "y")
      end
      session.record_episode(kind: "downstream", payload: {}, occurred_at: decision.decided_at + 5)

      expect(decision.impact).to be_a(::ActiveRecord::Relation)
      expect(decision.impact.pluck(:kind)).to include("downstream")
    end
  end

  describe "#alternatives_considered" do
    it "returns rejected options (not the chosen) each enriched with an evidence slice" do
      ::Vv::Graph::Sparql.bulk_insert(
        [["urn:mm:order:42", "mm:status", '"open"', iri]], raw: true,
      )
      decision = Vv::Decision.deliberate(scope: session, context: "x") do |ctx|
        ctx.consider(option: :cancel, grounded_in: ["urn:mm:order:42"])
        ctx.consider(option: :hold,   grounded_in: [])
        ctx.decide!(option: :hold, because: "y")
      end

      considered = decision.alternatives_considered
      expect(considered.map { |a| a["option"] }).to eq(["cancel"])
      slice = considered.first["evidence"]
      expect(slice).to be_a(Vv::Decision::EvidenceSlice)
      expect(slice.iris).to eq(["urn:mm:order:42"])
    end
  end

  describe "#evidence_slice" do
    it "unions grounding IRIs across alternatives and omits retracted IRIs" do
      ::Vv::Graph::Sparql.bulk_insert(
        [["urn:mm:order:42", "mm:status", '"open"', iri]], raw: true,
      )
      decision = Vv::Decision.deliberate(scope: session, context: "x") do |ctx|
        ctx.consider(option: :cancel, grounded_in: ["urn:mm:order:42", "urn:mm:order:99"])
        ctx.decide!(option: :cancel, because: "y")
      end

      # order:99 has no triples in Silver → omitted silently.
      expect(decision.evidence_slice.iris).to eq(["urn:mm:order:42"])
    end
  end

  describe "#reasoning_trace" do
    it "round-trips the reasoning payload with symbolized keys" do
      decision = Vv::Decision.deliberate(scope: session, context: "x") do |ctx|
        ctx.reason_with(model: :m, prompt: "p", completion: "c")
        ctx.decide!(option: :a, because: "y")
      end
      expect(decision.reasoning_trace).to eq(model: "m", prompt: "p", completion: "c")
    end
  end
end
