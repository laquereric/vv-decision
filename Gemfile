# frozen_string_literal: true

source "https://rubygems.org"

# Path-vendored siblings. `vv-memory` is the primary integration
# point (Conformer Extractor interface, Scoped concern,
# record_episode entrypoint). `vv-graph` is declared transitively
# but pinned via path so Bundler resolves a single checkout across
# all three gems.
gem "vv-memory", path: "../vv-memory"
gem "vv-graph",  path: "../vv-graph"

# Specify dependencies in vv-decision.gemspec.
gemspec
