# frozen_string_literal: true

module Vv
  module Decision
    # PLAN_0_1_0 Phase C — read-only value object wrapping the rows
    # returned by a `ctx.recall(query:)` SPARQL SELECT.
    #
    # The v0.1.0 recall convention is that the operator's query
    # projects `?s ?p ?o` (subject / predicate / object) — the
    # filter + `#iris` helpers read those bindings. Terms arrive in
    # the engine's N-Triples-ish form (IRIs as `<urn:…>` or bare,
    # literals as `"…"`); `#where` matches tolerantly against the
    # bracket-stripped form so callers can pass bare IRIs.
    #
    # No mutation surface — `#where` returns a new slice.
    class EvidenceSlice
      include Enumerable

      attr_reader :rows

      def initialize(rows)
        @rows = Array(rows).freeze
        freeze
      end

      def each(&block) = rows.each(&block)
      def count        = rows.length
      def empty?       = rows.empty?
      def to_a         = rows.dup

      # Filter by any of subject / predicate / object. Each argument,
      # when given, is matched against the corresponding `?s` / `?p`
      # / `?o` binding (bracket-stripped on both sides).
      def where(predicate: nil, subject: nil, object: nil)
        filtered = rows.select do |row|
          (predicate.nil? || term_eq?(row["p"], predicate)) &&
            (subject.nil? || term_eq?(row["s"], subject)) &&
            (object.nil?  || term_eq?(row["o"], object))
        end
        self.class.new(filtered)
      end

      # Unique subject IRIs (bracket-stripped), in first-seen order.
      def iris
        rows.map { |row| strip(row["s"]) }.compact.uniq
      end

      private

      def term_eq?(term, candidate)
        strip(term) == strip(candidate.to_s)
      end

      def strip(term)
        return nil if term.nil?
        s = term.to_s
        return s[1..-2] if s.start_with?("<") && s.end_with?(">")
        return s[1..-2] if s.start_with?('"') && s.end_with?('"')
        s
      end
    end
  end
end
