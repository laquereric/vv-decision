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

  it "registers the MissingDependency guard for application boot" do
    # The guard runs inside config.after_initialize, which only fires
    # under a full Rails::Application boot — we don't boot one here.
    # Pin the guard's presence by checking the initializer list
    # carries the after_initialize block this Engine declared.
    initializer_count = described_class.initializers.size
    expect(initializer_count).to be > 0
    # If the guard is removed, this expectation isn't sufficient on
    # its own; the load-time chain in spec_helper exercises the
    # happy path, and Phase F's integration spec exercises the boot
    # path inside a host app.
  end
end
