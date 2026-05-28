# frozen_string_literal: true

require "spec_helper"

# PLAN_0_1_0 Phase B — the Decision aggregate root.
RSpec.describe Vv::Decision::Decision, :requires_extension do
  let(:session_class) do
    Class.new(::ActiveRecord::Base) do
      self.table_name = "sessions"
      def self.name; "FakeSession"; end
    end
  end

  before(:each) { stub_const("FakeSession", session_class) }

  let(:session) { session_class.create!(name: "S1") }

  it "persists with scope + context and round-trips the JSON columns" do
    d = described_class.create!(
      scope:             session,
      context:           "should we cancel order 42?",
      alternatives:      [{ "option" => "hold", "grounded_in_iris" => ["urn:mm:order:17"] }],
      reasoning_payload: { "model" => "claude_opus_4_7" },
    )
    d.reload
    expect(d.context).to eq("should we cancel order 42?")
    expect(d.alternatives).to eq([{ "option" => "hold", "grounded_in_iris" => ["urn:mm:order:17"] }])
    expect(d.reasoning_payload).to eq("model" => "claude_opus_4_7")
  end

  it "requires a context" do
    d = described_class.new(scope: session)
    expect(d.valid?).to be(false)
    expect(d.errors[:context]).not_to be_empty
  end

  it "enforces provenance_id uniqueness where non-null" do
    described_class.create!(scope: session, context: "x", provenance_id: "p1")
    expect {
      described_class.create!(scope: session, context: "y", provenance_id: "p1")
    }.to raise_error(::ActiveRecord::RecordNotUnique)
  end

  it "permits multiple decisions with nil provenance_id" do
    described_class.create!(scope: session, context: "x")
    expect {
      described_class.create!(scope: session, context: "y")
    }.not_to raise_error
  end

  it "resolves the polymorphic scope back to the AR record" do
    d = described_class.create!(scope: session, context: "x")
    expect(d.scope).to eq(session)
  end

  it "decided? is false until decided_at is set" do
    d = described_class.create!(scope: session, context: "x")
    expect(d.decided?).to be(false)
    d.update!(decided_at: Time.now, decided_option: "hold")
    expect(d.decided?).to be(true)
    expect(d.option).to eq(:hold)
  end

  describe "scopes" do
    it ":decided / :since / :for_option filter as expected" do
      t0 = Time.utc(2026, 1, 1)
      described_class.create!(scope: session, context: "a") # undecided
      described_class.create!(scope: session, context: "b", decided_at: t0, decided_option: "hold")
      described_class.create!(scope: session, context: "c", decided_at: t0 + 60, decided_option: "cancel")

      expect(described_class.decided.count).to eq(2)
      expect(described_class.since(t0 + 30).count).to eq(1)
      expect(described_class.for_option(:hold).count).to eq(1)
    end
  end

  it "associates the two episode FK columns to Vv::Memory::Episode" do
    ctx_ep = ::Vv::Memory::Episode.create!(scope: session, kind: "decision_context", occurred_at: Time.now)
    out_ep = ::Vv::Memory::Episode.create!(scope: session, kind: "decision_outcome", occurred_at: Time.now)
    d = described_class.create!(
      scope: session, context: "x",
      decision_context_episode: ctx_ep,
      decision_outcome_episode: out_ep,
    )
    d.reload
    expect(d.decision_context_episode).to eq(ctx_ep)
    expect(d.decision_outcome_episode).to eq(out_ep)
  end
end
