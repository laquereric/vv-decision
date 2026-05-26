# frozen_string_literal: true

require_relative "lib/vv/decision/version"

Gem::Specification.new do |spec|
  spec.name        = "vv-decision"
  spec.version     = Vv::Decision::VERSION
  spec.authors     = ["MagenticMarket contributors"]
  spec.email       = ["substrate@magenticmarket.ai"]

  spec.summary     = "The third concern above memory: the agent's reasoning loop as a first-class lifecycle."
  spec.description = <<~DESC.strip
    `vv-decision` owns the forward-acting flow — context → query →
    reasoning → decision → action → impact — and persists each step's
    provenance as a `Decision` aggregate root. Reuses `vv-memory`'s
    Bronze (for the flow episodes) and Silver (for `vvdec:`-namespaced
    triples emitted via a `DecisionExtractor` Conformer subclass).

    v0.1.0 ships the minimum viable aggregate: `Vv::Decision.deliberate`
    entrypoint, `Vv::Decision::Decision` AR aggregate root, the
    `DecisionExtractor` (registered with vv-memory's Conformer at boot),
    and four read-side traversal methods (trace_back,
    alternatives_considered, impact, evidence_slice). Class-level
    analytical facades, causal traversal, and Curator/Gold integration
    land in 0.2.0+. See `docs/plans/PLAN_0_1_0.md`.

    Status: v0.1.0 — unreleased.
  DESC

  spec.homepage    = "https://github.com/laquereric/vv-decision"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org" if Gem::Version.new(spec.version.to_s) >= Gem::Version.new("1.0.0")
  spec.metadata["source_code_uri"]   = "https://github.com/laquereric/vv-decision"
  spec.metadata["changelog_uri"]     = "https://github.com/laquereric/vv-decision/blob/main/CHANGELOG.md"

  spec.files = Dir[
    "lib/**/*.rb",
    "app/**/*.rb",
    "db/migrate/*.rb",
    "README.md",
    "LICENSE",
    "CHANGELOG.md",
    "VERSION",
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord",    ">= 8.0"
  spec.add_dependency "activesupport",   ">= 8.0"
  spec.add_dependency "railties",        ">= 8.0"

  # PLAN_0_1_0 Phase A — the Conformer Extractor interface is the
  # primary integration point. The boot-time `MissingDependency`
  # guard in Engine checks `defined?(::Vv::Memory::Scoped)` AND
  # `defined?(::Vv::Memory::Conformer::Extractor)` — the
  # authoritative readiness signal.
  spec.add_dependency "vv-memory",       ">= 0.2.0"

  # PLAN_0_1_0 Phase A — declared explicitly (transitively pulled by
  # vv-memory) so a tightening of this gem's read-side surface
  # (which uses `Vv::Graph::Scope` + SPARQL-star) is visible at
  # gemspec-resolution time.
  spec.add_dependency "vv-graph", "~> 0.15"

  spec.add_development_dependency "rspec",   "~> 3.13"
  spec.add_development_dependency "rake",    "~> 13.0"
  spec.add_development_dependency "sqlite3", "~> 2.4"
end
