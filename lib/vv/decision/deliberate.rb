# frozen_string_literal: true

module Vv
  module Decision
    # The five reserved Bronze episode kinds the decision flow emits.
    # Exported so consumers can exclude them from a paginated
    # `scope.memory_episodes` view:
    #   scope.memory_episodes.where.not(kind: Vv::Decision::EPISODE_KINDS)
    # These are DS-owned conventions, not vv-memory expectations.
    EPISODE_KINDS = %w[
      decision_context
      decision_query
      decision_consider
      decision_reasoning
      decision_outcome
    ].freeze

    module_function

    # PLAN_0_1_0 Phase D — register the DecisionExtractor with
    # vv-memory's Conformer so `scope.conform_now!` routes
    # `decision_outcome` episodes through it. Idempotent (vv-memory's
    # registry treats same-class re-registration as a no-op), so it's
    # safe to call from both the Engine's `after_initialize` and a
    # non-Rails spec harness.
    #
    # NOTE: vv-memory v0.2.2 shipped `StrategySelector.register(kind:,
    # extractor_class:)` — NOT the `ExtractorRegistry.unregister(...)`
    # API this gem's PLAN_0_1_0 Phase D originally sketched. There is
    # no per-class unregister; operators who want to suppress decision
    # triples thread a custom `StrategySelector` that doesn't route
    # `decision_outcome` (CR_DS B1 option B). See PLAN_0_1_0 Phase D.
    def register_extractor!
      require "vv/memory/conformer"
      require "vv/decision/decision_extractor"
      ::Vv::Memory::Conformer::StrategySelector.register(
        kind:            "decision_outcome",
        extractor_class: ::Vv::Decision::DecisionExtractor,
      )
    end

    # PLAN_0_1_0 Phase C — the forward-acting entrypoint.
    #
    # Opens a transaction, records a `decision_context` Bronze
    # episode, builds a `Decision` aggregate, and yields a
    # `DeliberationContext` to the block. The whole flow (Decision
    # row + every Bronze episode) is atomic: if the block raises,
    # everything rolls back and the exception propagates.
    #
    # After the block returns:
    #   - if `ctx.decide!` ran, the Decision is persisted + decided;
    #   - otherwise the Decision is persisted with `decided_at: nil`
    #     (the abandoned-deliberation case — the row survives as
    #     audit; the caller branches on `decision.decided?`).
    #
    # @param scope [#record_episode, #memory_silver] a record
    #   including `Vv::Memory::Scoped`
    # @return [Vv::Decision::Decision]
    def deliberate(scope:, context:, provenance_id: nil, &block)
      validate_entry!(scope: scope, context: context, block: block)

      ::Vv::Decision::Decision.transaction do
        context_episode = scope.record_episode(
          kind:    "decision_context",
          payload: { context: context, provenance_id: provenance_id },
        )

        decision = ::Vv::Decision::Decision.new(
          scope:                    scope,
          context:                  context,
          decision_context_episode: context_episode,
          provenance_id:            provenance_id,
        )

        ctx = ::Vv::Decision::DeliberationContext.new(decision: decision, scope: scope)
        block.call(ctx)

        # decide! persists inline; an abandoned deliberation still
        # persists the row (decided_at stays nil) for audit.
        decision.save! unless decision.persisted?
        decision
      end
    end

    def validate_entry!(scope:, context:, block:)
      raise ::Vv::Decision::Errors::InvalidDeliberation, "scope is required" if scope.nil?
      raise ::Vv::Decision::Errors::InvalidDeliberation, "a block is required" if block.nil?
      if context.nil? || context.to_s.strip.empty?
        raise ::Vv::Decision::Errors::InvalidDeliberation, "context must be non-blank"
      end
      unless scope.is_a?(::Vv::Memory::Scoped)
        raise ::Vv::Decision::Errors::InvalidDeliberation,
              "scope must include Vv::Memory::Scoped (got #{scope.class})"
      end
    end
  end
end
