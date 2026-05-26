# frozen_string_literal: true

module Vv
  module Decision
    module Errors
      # Loading-time guard fired when the host bundle doesn't include
      # `vv-memory >= 0.2.0` (specifically, when either
      # `Vv::Memory::Scoped` or `Vv::Memory::Conformer::Extractor` is
      # undefined at `config.after_initialize` time). Raised by the
      # Engine.
      class MissingDependency < StandardError; end

      # Raised when `Vv::Decision.deliberate(scope:, context:, &block)`
      # is called with arguments that don't satisfy the entry contract
      # (missing scope, blank context, scope not including
      # Vv::Memory::Scoped, no block given).
      class InvalidDeliberation < StandardError; end

      # Raised when `DeliberationContext#decide!` is called twice in
      # one block. Mid-block changes of mind are expressed via
      # `consider(rejected_because:)` on the prior option, then a
      # fresh `consider` + `decide!` on the new one — but only one
      # `decide!` may commit per `deliberate` call.
      class AlreadyDecided < StandardError; end

      # Raised by `DeliberationContext#recall(depth:)` when given a
      # depth other than `:silver` in v0.1.0. The `:gold` and
      # `:bronze` paths land once `vv-memory` PLAN_0.4.0 ships and
      # `Vv::Memory.recall(...)` is available to delegate to.
      class RecallDepthUnsupported < ArgumentError; end

      # Defined but not raised by v0.1.0's `deliberate`. Operators may
      # use it themselves when their code expects a decision but
      # `decision.decided? == false` (the abandoned-deliberation case
      # where the block exited without calling `decide!`).
      class NoDecisionMade < StandardError; end
    end
  end
end
