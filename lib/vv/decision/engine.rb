# frozen_string_literal: true

require "rails/engine"

module Vv
  module Decision
    # The third concern above memory: the agent's reasoning loop as a
    # first-class lifecycle.
    #
    # v0.1.0 ships the minimum viable aggregate:
    # - `Vv::Decision.deliberate(scope:, context:, &block)` entrypoint
    #   (Phase C).
    # - `Vv::Decision::Decision` AR aggregate root (Phase B).
    # - `Vv::Decision::DecisionExtractor` registered with vv-memory's
    #   Conformer at boot (Phase D).
    # - Four read-side traversal methods on `Decision` (Phase E).
    #
    # Class-level analytical facades, causal (`vvdec:caused_by`)
    # traversal, and Curator/Gold integration land in 0.2.0+. See
    # `docs/plans/PLAN_0_1_0.md`.
    class Engine < ::Rails::Engine
      isolate_namespace Vv::Decision

      config.eager_load_namespaces << Vv::Decision

      # PLAN_0_1_0 Phase A — refuse to boot if the vv-memory
      # dependency is unavailable. We check the constants rather than
      # the gem version because the gemspec already pins
      # `vv-memory >= 0.2.0`; this guard catches the case where the
      # constants are undefined (e.g., the operator forgot to add
      # `require "vv/memory"` to their Gemfile or a custom boot path
      # doesn't pull it in).
      #
      # Two-constant check: `Vv::Memory::Scoped` is the entrypoint
      # for episode recording; `Vv::Memory::Conformer::Extractor` is
      # the Phase D integration point (the base class
      # `DecisionExtractor` subclasses). Either being absent means
      # the dependency is too old or partial.
      config.after_initialize do
        unless defined?(::Vv::Memory::Scoped) && defined?(::Vv::Memory::Conformer::Extractor)
          raise ::Vv::Decision::Errors::MissingDependency,
                "Vv::Decision depends on Vv::Memory::Scoped + " \
                "Vv::Memory::Conformer::Extractor (vv-memory >= 0.2.0). " \
                "bundle vv-memory 0.2.0+ alongside vv-decision."
        end
      end
    end
  end
end
