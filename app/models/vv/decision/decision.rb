# frozen_string_literal: true

require "active_record"

module Vv
  module Decision
    # PLAN_0_1_0 Phase B — the aggregate root.
    #
    # One row per `Vv::Decision.deliberate(...)` call. No state
    # machine: the `decided_at` timestamp doubles as the "committed"
    # flag. `decided_at: nil` means `deliberate` was entered but
    # `ctx.decide!` was never called — the row survives as evidence
    # of an abandoned deliberation (raising would lose the audit).
    #
    # Polymorphic `scope` mirrors `Vv::Memory::Episode`'s shape so a
    # Decision and its scope's episode stream join on
    # `(scope_type, scope_id)`. The two FK columns reference
    # `vv_memory_episodes.id` (vv-memory's pinned table + bigint PK,
    # CR_DS B5).
    class Decision < ::ActiveRecord::Base
      self.table_name = "vv_decision_decisions"

      belongs_to :scope, polymorphic: true

      belongs_to :decision_context_episode,
                 class_name:  "Vv::Memory::Episode",
                 foreign_key: :decision_context_episode_id,
                 optional:    true
      belongs_to :decision_outcome_episode,
                 class_name:  "Vv::Memory::Episode",
                 foreign_key: :decision_outcome_episode_id,
                 optional:    true

      validates :context, presence: true

      scope :decided,    -> { where.not(decided_at: nil) }
      scope :since,      ->(t) { where("decided_at >= ?", t) }
      scope :for_option, ->(opt) { where(decided_option: opt.to_s) }

      def decided?
        !decided_at.nil?
      end

      def option
        decided_option&.to_sym
      end

      # PLAN_0_1_0 Phase E — read-side traversal.
      #
      # v0.1.0 is timeline-shaped, not causal: prior decisions in the
      # SAME scope whose outcome episode predates this decision's
      # context episode. The causal (`vvdec:caused_by`) chain lands
      # in v0.2.0 once action emission ships.
      def trace_back
        ctx_ep = decision_context_episode
        return [] unless ctx_ep

        self.class
          .where(scope_type: scope_type, scope_id: scope_id)
          .where.not(id: id)
          .joins(
            "INNER JOIN vv_memory_episodes vme " \
            "ON vme.id = vv_decision_decisions.decision_outcome_episode_id",
          )
          .where("vme.occurred_at < ?", ctx_ep.occurred_at)
          .to_a
      end

      # The rejected options enriched with a reconstructed evidence
      # slice (re-queried against live Silver). Excludes the chosen
      # option.
      def alternatives_considered
        (alternatives || [])
          .reject { |alt| alt["option"] == decided_option }
          .map { |alt| alt.merge("evidence" => evidence_for(alt["grounded_in_iris"] || [])) }
      end

      # Downstream Bronze episodes in the same scope. v0.1.0 uses the
      # timeline-correlation heuristic (everything after the decision
      # is potential impact). Returns a Relation so callers paginate.
      def impact
        return ::Vv::Memory::Episode.none unless decided_at

        ::Vv::Memory::Episode
          .where(scope_type: scope_type, scope_id: scope_id)
          .where("occurred_at > ?", decided_at)
      end

      # EvidenceSlice over the union of grounding IRIs across all
      # alternatives, hydrated from live Silver. Retracted IRIs omit
      # silently; the original IRIs remain in the JSON column for audit.
      def evidence_slice
        iris = (alternatives || []).flat_map { |alt| alt["grounded_in_iris"] || [] }.uniq
        evidence_for(iris)
      end

      # The stored reasoning trace with symbolized keys.
      def reasoning_trace
        (reasoning_payload || {}).transform_keys(&:to_sym)
      end

      private

      def evidence_for(iris)
        return ::Vv::Decision::EvidenceSlice.new([]) if iris.nil? || iris.empty?

        values = iris.map { |i| "<#{i}>" }.join(" ")
        result = ::Vv::Graph::Sparql.select(
          "SELECT ?s ?p ?o WHERE { VALUES ?s { #{values} } ?s ?p ?o }",
          graph: scope.memory_silver[:iri],
        )
        ::Vv::Decision::EvidenceSlice.new(result[:ok] ? (result[:results] || []) : [])
      end
    end
  end
end
