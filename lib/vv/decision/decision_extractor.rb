# frozen_string_literal: true

require "vv/memory/conformer/extractor"
require "vv/memory/conformer/triple_proposal"

module Vv
  module Decision
    # PLAN_0_1_0 Phase D — promotes `decision_outcome` Bronze
    # episodes into `vvdec:`-namespaced Silver triples.
    #
    # Subclasses `Vv::Memory::Conformer::Extractor` to preserve
    # vv-memory's invariant that the Conformer is the only
    # Bronze → Silver path. Registered against the
    # `"decision_outcome"` kind via
    # `Vv::Memory::Conformer::StrategySelector.register` at Engine
    # boot (see `Vv::Decision.register_extractor!`). The parent
    # Conformer wraps each emitted triple with the `vvmem:`
    # provenance annotations — this extractor only emits the
    # `vvdec:` content.
    class DecisionExtractor < ::Vv::Memory::Conformer::Extractor
      VVDEC    = "urn:vv-decision:annotation:"
      RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
      XSD_DATETIME = "http://www.w3.org/2001/XMLSchema#dateTime"

      # Pinned per CR_DS B2 (vv-memory v0.2.2 accepts any non-blank
      # revision string; DS keeps the self-documenting path form).
      def revision
        "vv-decision/v0.1.0/DecisionExtractor"
      end

      # DS-side convention (not a vv-memory expectation) — lets a
      # composed selector short-circuit the wrong kind. The registry
      # already routes by kind, so this is belt-and-braces.
      def applies_to?(episode)
        episode.kind == "decision_outcome"
      end

      def extract(episode, context:)
        decision = ::Vv::Decision::Decision.find_by(decision_outcome_episode_id: episode.id)
        return [] unless decision&.decided?

        subject  = "urn:vv-decision:decision:#{decision.id}"
        proposals = []

        # Headline type triple.
        proposals << triple(s: subject, p: RDF_TYPE, o: "<#{VVDEC}Decision>")

        # Scalar content.
        proposals << triple(s: subject, p: "#{VVDEC}context",        o: literal(decision.context))
        proposals << triple(s: subject, p: "#{VVDEC}decided_option", o: literal(decision.decided_option))
        proposals << triple(s: subject, p: "#{VVDEC}because",        o: literal(decision.because)) if decision.because
        proposals << triple(
          s: subject, p: "#{VVDEC}decided_at",
          o: %("#{decision.decided_at.utc.iso8601}"^^<#{XSD_DATETIME}>),
        )

        # Grounding evidence — one triple per IRI across all alternatives.
        grounding_iris(decision).each do |iri|
          proposals << triple(s: subject, p: "#{VVDEC}grounded_in", o: "<#{iri}>")
        end

        # Rejected alternatives (the chosen option is NOT its own alternative_to).
        rejected_options(decision).each do |opt|
          proposals << triple(s: subject, p: "#{VVDEC}alternative_to", o: literal(opt))
        end

        # Reasoning trace — model only; prompt/completion stay in Bronze.
        if (model = decision.reasoning_payload["model"])
          proposals << triple(s: subject, p: "#{VVDEC}reasoned_with", o: literal(model))
        end

        proposals
      end

      private

      def grounding_iris(decision)
        decision.alternatives
          .flat_map { |alt| alt["grounded_in_iris"] || [] }
          .uniq
      end

      def rejected_options(decision)
        decision.alternatives
          .map { |alt| alt["option"] }
          .compact
          .uniq
          .reject { |opt| opt == decision.decided_option }
      end

      def literal(value)
        %("#{value.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}")
      end

      def triple(s:, p:, o:)
        ::Vv::Memory::Conformer::TripleProposal.build(s: s, p: p, o: o, confidence: 1.0)
      end
    end
  end
end
