# frozen_string_literal: true

# Mirrors vv-memory's spec/support/extension_environment.rb. Boots
# ActiveRecord + sqlite3 with an in-memory connection and loads the
# compiled sqlite-sparql extension on first access. If any
# prerequisite is missing, `.available?` returns false and
# `.skip_reason` carries the verbatim hint — specs tagged
# `:requires_extension` skip in that case rather than failing the
# suite.
#
# Phase A doesn't itself require the extension (the Engine guard
# only inspects constants), but the harness loads it eagerly so
# Phases B–F can light up `:requires_extension` specs without
# re-wiring the bootstrap.
module Vv
  module Decision
    module SpecSupport
      module ExtensionEnvironment
        class << self
          def available?
            ensure_attempted!
            @available
          end

          def skip_reason
            ensure_attempted!
            @skip_reason
          end

          def reset_store!
            return unless available?
            ::ActiveRecord::Base.connection.execute("SELECT rdf_clear()")
          end

          private

          def ensure_attempted!
            return if defined?(@attempted)
            @attempted = true
            @available = false
            @skip_reason = nil
            attempt_bootstrap
          end

          def attempt_bootstrap
            begin
              require "active_record"
              require "sqlite3"
              require "vv-graph"
            rescue LoadError => e
              @skip_reason = "skipping — required gems not loadable (#{e.message}). Run `bundle install` inside vendor/vv-decision."
              return
            end

            ext_path = ::Vv::Graph::Loader.extension_path
            unless ext_path
              @skip_reason = build_hint
              return
            end

            begin
              ::ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
              ::Vv::Graph::Loader.ensure_extension_loaded!
              ::ActiveRecord::Base.connection.execute("SELECT rdf_count()")
            rescue StandardError => e
              @skip_reason = "skipping — extension found at #{ext_path} but failed to load: #{e.message}"
              return
            end

            @available = true
          end

          def build_hint
            <<~HINT.strip
              skipping — sqlite-sparql extension not built. Build with:
                cd vendor/sqlite-sparql && cargo build --release
              Or set MM_SQLITE_SPARQL_PATH to an already-built .dylib / .so.
            HINT
          end
        end
      end
    end
  end
end
