# frozen_string_literal: true

# Order matters: `lib` before `app/models` so a bare
# `require "vv/decision/..."` resolves the lib loader first. The
# canonical `Vv::Decision::Decision` AR model lives under
# `app/models/` (Rails autoloads it in a host); adding it to
# LOAD_PATH lets the non-Rails spec harness require it. (Same
# load-path discipline vv-memory's spec_helper learned in v0.2.2.)
$LOAD_PATH.unshift File.expand_path("../app/models", __dir__)
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# vv-memory ships its AR models (Episode, Conformer::Cursor /
# QualityRecord) under its own `app/models`, which Bundler does not
# add to the load path for a path gem (only `lib` is a require
# path). In a Rails host the vv-memory Engine eager-loads them;
# this non-Rails spec harness must add the sibling's app/models so
# `require "vv/memory/episode"` (inside vv/memory.rb) resolves and
# the FakeSession#memory_episodes association can find the class.
#
# APPEND (not unshift): vv-memory's `lib` is already on the path
# (Bundler, path gem). For the one path that exists in BOTH trees —
# `vv/memory/conformer` (lib loader vs. the one-line app/models
# Zeitwerk anchor) — `lib` must win, so app/models goes to the back.
# Episode / Conformer::Cursor / QualityRecord exist only under
# app/models, so they still resolve from the appended entry.
$LOAD_PATH << File.expand_path("../../vv-memory/app/models", __dir__)

require_relative "support/extension_environment"
require_relative "support/active_storage_environment"
require_relative "support/schema"

# Bring AR + AS up *before* requiring the gem so `Vv::Memory`'s
# eager `require "vv/memory/episode"` (which carries
# `has_one_attached :payload_blob`) sees the extended
# `ActiveRecord::Base` at class-definition time. If the native
# extension is absent we still establish a vanilla AR connection
# so contract specs (version, errors, engine constants) load —
# `:requires_extension` specs skip via the configure-time check.
if Vv::Decision::SpecSupport::ExtensionEnvironment.available?
  Vv::Decision::SpecSupport::ActiveStorageEnvironment.setup!
else
  require "active_record"
  require "sqlite3"
  ::ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
  Vv::Decision::SpecSupport::ActiveStorageEnvironment.setup!
end

# Define `Rails::Engine` before requiring the gem so the
# `if defined?(::Rails::Engine)` guard in `vv/decision.rb` actually
# loads `Vv::Decision::Engine` (and transitively `Vv::Memory::Engine`).
# Defining the Engine classes is side-effect-free without a full app
# boot — `config.after_initialize` blocks register but don't fire.
# (railties is a declared dependency.)
require "rails/engine"

require "vv/decision"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  # Specs that tag `:requires_extension` round-trip real SPARQL
  # through the compiled sqlite-sparql binary. Without it, those
  # specs skip with a one-line build hint rather than failing.
  config.before(:each, :requires_extension) do
    unless Vv::Decision::SpecSupport::ExtensionEnvironment.available?
      skip Vv::Decision::SpecSupport::ExtensionEnvironment.skip_reason
    end
    Vv::Decision::SpecSupport::ExtensionEnvironment.reset_store!
    Vv::Decision::SpecSupport::ActiveStorageEnvironment.setup!
    Vv::Decision::SpecSupport::ActiveStorageEnvironment.reset!
    Vv::Decision::SpecSupport::ActiveStorageEnvironment.setup!
    Vv::Decision::SpecSupport::Schema.ensure!
    Vv::Decision::SpecSupport::Schema.reset!
    ::Vv::Graph::EtherealGraph.reset! if defined?(::Vv::Graph::EtherealGraph)
  end
end
