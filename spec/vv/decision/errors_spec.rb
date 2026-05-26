# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vv::Decision::Errors do
  it "exposes the v0.1.0 pinned error classes" do
    expect(described_class::MissingDependency).to be_a(Class)
    expect(described_class::MissingDependency.ancestors).to include(StandardError)

    expect(described_class::InvalidDeliberation).to be_a(Class)
    expect(described_class::InvalidDeliberation.ancestors).to include(StandardError)

    expect(described_class::AlreadyDecided).to be_a(Class)
    expect(described_class::AlreadyDecided.ancestors).to include(StandardError)

    expect(described_class::RecallDepthUnsupported).to be_a(Class)
    expect(described_class::RecallDepthUnsupported.ancestors).to include(ArgumentError)

    expect(described_class::NoDecisionMade).to be_a(Class)
    expect(described_class::NoDecisionMade.ancestors).to include(StandardError)
  end
end
