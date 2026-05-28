# frozen_string_literal: true

module Vv
  module Decision
    # PLAN_0_1_0 Phase C — the block-scoped flow recorder.
    #
    # Yielded to the `Vv::Decision.deliberate(...)` block. Each flow
    # method (a) mutates the in-flight `Decision` aggregate and/or
    # (b) appends a Bronze flow episode to the scope's stream. The
    # five reserved episode kinds are exported as
    # `Vv::Decision::EPISODE_KINDS`.
    #
    # Forward-acting only: nothing here reads Silver back except
    # `#recall`, which is the one query step. The backward-acting
    # promotion to `vvdec:` Silver triples is the Conformer's job
    # (Phase D), triggered separately via `scope.conform_now!`.
    class DeliberationContext
      def initialize(decision:, scope:)
        @decision = decision
        @scope    = scope
        @decided  = false
      end

      attr_reader :decision

      # v0.1.0 thin recall: the operator writes a SPARQL string that
      # projects `?s ?p ?o`. Returns an EvidenceSlice over the rows
      # in the scope's Silver graph. Records a `decision_query`
      # episode with the query text + result count.
      #
      # `depth:` is `:silver` only in v0.1.0; `:gold` / `:bronze`
      # raise `RecallDepthUnsupported` (lifts when vv-memory
      # PLAN_0.4.0's `Vv::Memory.recall(...)` ships).
      def recall(query:, depth: :silver)
        unless depth == :silver
          raise ::Vv::Decision::Errors::RecallDepthUnsupported,
                "recall(depth: #{depth.inspect}) unsupported in v0.1.0 — only :silver. " \
                "The :gold / :bronze paths land once vv-memory PLAN_0.4.0 " \
                "(Vv::Memory.recall) ships."
        end

        result = ::Vv::Graph::Sparql.select(query, graph: @scope.memory_silver[:iri])
        rows   = result[:ok] ? (result[:results] || []) : []
        slice  = ::Vv::Decision::EvidenceSlice.new(rows)

        @scope.record_episode(
          kind:    "decision_query",
          payload: { query: query, depth: depth.to_s, result_count: slice.count },
        )
        slice
      end

      # Append a candidate option to the in-flight decision's
      # alternatives. `grounded_in` is an EvidenceSlice (or anything
      # responding to #iris, or an Array of IRI strings). Records a
      # `decision_consider` episode.
      def consider(option:, grounded_in: nil, rejected_because: nil)
        iris = grounding_iris(grounded_in)
        entry = {
          "option"           => option.to_s,
          "grounded_in_iris" => iris,
          "rejected_because" => rejected_because,
        }
        @decision.alternatives = (@decision.alternatives || []) + [entry]

        @scope.record_episode(
          kind:    "decision_consider",
          payload: entry,
        )
        self
      end

      # Record a model-reasoning trace. The gem does NOT invoke an
      # LLM in v0.1.0 — the operator supplies the completion. Records
      # a `decision_reasoning` episode.
      def reason_with(model:, prompt:, completion: nil)
        @decision.reasoning_payload = {
          "model"      => model.to_s,
          "prompt"     => prompt,
          "completion" => completion,
        }
        @scope.record_episode(
          kind:    "decision_reasoning",
          payload: @decision.reasoning_payload,
        )
        self
      end

      # Commit the decision. Sets decided_option / because /
      # decided_at, persists, appends a `decision_outcome` episode,
      # and back-fills the outcome episode FK. Only one decide! may
      # commit per deliberate call.
      def decide!(option:, because:)
        raise ::Vv::Decision::Errors::AlreadyDecided,
              "decide! already called in this deliberate block" if @decided

        @decided = true
        @decision.decided_option = option.to_s
        @decision.because        = because
        @decision.decided_at     = Time.current
        @decision.save!

        outcome = @scope.record_episode(
          kind:    "decision_outcome",
          payload: { option: option.to_s, because: because },
        )
        @decision.update!(decision_outcome_episode_id: outcome.id)
        @decision
      end

      def decided?
        @decided
      end

      private

      def grounding_iris(grounded_in)
        return [] if grounded_in.nil?
        return grounded_in.iris if grounded_in.respond_to?(:iris)
        Array(grounded_in).map(&:to_s)
      end
    end
  end
end
