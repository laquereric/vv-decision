# frozen_string_literal: true

require "spec_helper"

# PLAN_0_1_0 Phase C — deliberate entrypoint + DeliberationContext.
RSpec.describe "Vv::Decision.deliberate", :requires_extension do
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
  before(:each) { session.memory_silver[:hydrate!].call }

  it "returns a persisted, decided Decision with paired context+outcome episodes" do
    decision = Vv::Decision.deliberate(scope: session, context: "cancel order 42?") do |ctx|
      ctx.decide!(option: :hold, because: "dep on order 17")
    end

    expect(decision).to be_persisted
    expect(decision.decided?).to be(true)
    expect(decision.decided_option).to eq("hold")
    expect(decision.because).to eq("dep on order 17")
    expect(decision.decision_context_episode.kind).to eq("decision_context")
    expect(decision.decision_outcome_episode.kind).to eq("decision_outcome")
  end

  it "rolls back ALL state when the block raises" do
    expect {
      Vv::Decision.deliberate(scope: session, context: "boom") do |_ctx|
        raise "kaboom"
      end
    }.to raise_error("kaboom")

    expect(Vv::Decision::Decision.count).to eq(0)
    expect(session.memory_episodes.count).to eq(0)
  end

  it "persists an undecided Decision when the block never calls decide!" do
    decision = Vv::Decision.deliberate(scope: session, context: "noop") { |_ctx| }
    expect(decision).to be_persisted
    expect(decision.decided?).to be(false)
  end

  it "raises AlreadyDecided on a second decide!" do
    expect {
      Vv::Decision.deliberate(scope: session, context: "x") do |ctx|
        ctx.decide!(option: :a, because: "first")
        ctx.decide!(option: :b, because: "second")
      end
    }.to raise_error(Vv::Decision::Errors::AlreadyDecided)
  end

  it "enforces provenance_id uniqueness at outer-transaction commit" do
    Vv::Decision.deliberate(scope: session, context: "x", provenance_id: "dup") do |ctx|
      ctx.decide!(option: :a, because: "y")
    end
    expect {
      Vv::Decision.deliberate(scope: session, context: "x2", provenance_id: "dup") do |ctx|
        ctx.decide!(option: :a, because: "y")
      end
    }.to raise_error(::ActiveRecord::RecordNotUnique)
  end

  describe "entry validation" do
    it "rejects a blank context" do
      expect {
        Vv::Decision.deliberate(scope: session, context: "  ") { |_ctx| }
      }.to raise_error(Vv::Decision::Errors::InvalidDeliberation, /context/)
    end

    it "rejects a scope that does not include Vv::Memory::Scoped" do
      plain = Class.new(::ActiveRecord::Base) { self.table_name = "sessions"; def self.name; "Plain"; end }.create!
      expect {
        Vv::Decision.deliberate(scope: plain, context: "x") { |_ctx| }
      }.to raise_error(Vv::Decision::Errors::InvalidDeliberation, /Scoped/)
    end

    it "rejects a missing block" do
      expect {
        Vv::Decision.deliberate(scope: session, context: "x")
      }.to raise_error(Vv::Decision::Errors::InvalidDeliberation, /block/)
    end
  end

  describe "flow methods" do
    it "consider appends an alternative and records a decision_consider episode" do
      decision = Vv::Decision.deliberate(scope: session, context: "x") do |ctx|
        ctx.consider(option: :cancel, grounded_in: ["urn:mm:order:42"])
        ctx.decide!(option: :cancel, because: "y")
      end
      expect(decision.alternatives.map { |a| a["option"] }).to include("cancel")
      expect(decision.alternatives.first["grounded_in_iris"]).to eq(["urn:mm:order:42"])
      expect(session.memory_episodes.of_kind("decision_consider").count).to eq(1)
    end

    it "reason_with sets reasoning_payload and records a decision_reasoning episode" do
      decision = Vv::Decision.deliberate(scope: session, context: "x") do |ctx|
        ctx.reason_with(model: :claude_opus_4_7, prompt: "why?", completion: "because")
        ctx.decide!(option: :a, because: "y")
      end
      expect(decision.reasoning_payload).to eq(
        "model" => "claude_opus_4_7", "prompt" => "why?", "completion" => "because",
      )
      expect(session.memory_episodes.of_kind("decision_reasoning").count).to eq(1)
    end

    it "recall(depth: :gold) raises RecallDepthUnsupported" do
      expect {
        Vv::Decision.deliberate(scope: session, context: "x") do |ctx|
          ctx.recall(query: "SELECT ?s ?p ?o WHERE { ?s ?p ?o }", depth: :gold)
        end
      }.to raise_error(Vv::Decision::Errors::RecallDepthUnsupported)
    end

    it "recall returns an EvidenceSlice and records a decision_query episode" do
      ::Vv::Graph::Sparql.bulk_insert(
        [["urn:mm:order:42", "mm:status", '"open"', session.memory_silver[:iri]]], raw: true,
      )
      decision = Vv::Decision.deliberate(scope: session, context: "x") do |ctx|
        slice = ctx.recall(query: "SELECT ?s ?p ?o WHERE { ?s ?p ?o }")
        expect(slice).to be_a(Vv::Decision::EvidenceSlice)
        expect(slice.where(predicate: "mm:status").iris).to eq(["urn:mm:order:42"])
        ctx.decide!(option: :a, because: "y")
      end
      expect(session.memory_episodes.of_kind("decision_query").count).to eq(1)
      expect(decision).to be_decided
    end
  end
end
