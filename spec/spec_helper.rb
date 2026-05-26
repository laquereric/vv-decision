# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

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
