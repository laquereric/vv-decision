# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vv::Decision::Engine do
  it "is a Rails::Engine subclass" do
    expect(described_class.ancestors).to include(::Rails::Engine)
  end

  it "isolates the Vv::Decision namespace" do
    expect(described_class.isolated?).to be(true)
    expect(described_class.railtie_namespace).to eq(Vv::Decision)
  end

  it "loads with the vv-memory dependency present" do
    # Loading the spec_helper has already chained `require "vv/decision"`,
    # which transitively requires "vv/memory". Both integration-point
    # constants the Engine guard checks must be defined.
    expect(defined?(::Vv::Memory::Scoped)).to eq("constant")
    expect(defined?(::Vv::Memory::Conformer::Extractor)).to eq("constant")
  end

  it "register_extractor! (invoked at boot) idempotently binds the DecisionExtractor" do
    # The Engine's config.after_initialize calls
    # `Vv::Decision.register_extractor!` under a full app boot — which
    # we don't run here. Exercise that registration directly: it's
    # idempotent (vv-memory's StrategySelector treats same-class
    # re-registration as a no-op) and binds the "decision_outcome"
    # kind to DecisionExtractor.
    Vv::Decision.register_extractor!
    expect { Vv::Decision.register_extractor! }.not_to raise_error
    expect(::Vv::Memory::Conformer::StrategySelector.registered_for("decision_outcome"))
      .to eq(::Vv::Decision::DecisionExtractor)
  end
end
