# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vv::Decision::VERSION do
  it "matches the VERSION file" do
    expected = File.read(File.expand_path("../../../VERSION", __dir__)).strip
    expect(Vv::Decision::VERSION).to eq(expected)
  end

  it "is 0.1.0 at this checkpoint" do
    expect(Vv::Decision::VERSION).to eq("0.1.0")
  end
end
