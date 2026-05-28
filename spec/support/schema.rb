# frozen_string_literal: true

# Sets up the schema vv-decision specs need on the in-memory SQLite
# connection. Idempotent — safe to call once per example.
#
# Phase A: only the tables `vv-memory`'s `require "vv/memory"` chain
# needs at class-definition time (so the `Vv::Memory::Episode` AR
# model loads cleanly) plus a `sessions` fixture table that Phase
# C/F integration specs will use as a scope.
#
# Phase B will add `vv_decision_decisions` here.
module Vv
  module Decision
    module SpecSupport
      module Schema
        class << self
          def ensure!
            conn = ::ActiveRecord::Base.connection

            unless conn.table_exists?(:vv_memory_episodes)
              ::ActiveRecord::Schema.define do
                create_table :vv_memory_episodes do |t|
                  t.references :scope, polymorphic: true, null: true, index: true
                  t.string     :kind,        null: false
                  t.string     :actor
                  t.text       :payload, null: false, default: "{}"
                  t.datetime   :occurred_at, null: false
                  t.string     :provenance_id
                  t.timestamps
                end
                add_index :vv_memory_episodes, :occurred_at
                add_index :vv_memory_episodes,
                          [:scope_type, :scope_id, :occurred_at],
                          name: "index_vv_memory_episodes_on_scope_and_time"
                add_index :vv_memory_episodes, :provenance_id,
                          unique: true,
                          where: "provenance_id IS NOT NULL"
              end
            end

            unless conn.table_exists?(:vv_memory_conformer_cursors)
              ::ActiveRecord::Schema.define do
                create_table :vv_memory_conformer_cursors do |t|
                  t.string :scope_type,         null: false
                  t.bigint :scope_id,           null: false
                  t.string :extractor_revision, null: false
                  t.bigint :last_episode_id
                  t.timestamps
                end
                add_index :vv_memory_conformer_cursors,
                          [:scope_type, :scope_id, :extractor_revision],
                          unique: true,
                          name: "index_vv_memory_conformer_cursors_uniq"
              end
            end

            unless conn.table_exists?(:vv_memory_conformer_quality)
              ::ActiveRecord::Schema.define do
                create_table :vv_memory_conformer_quality do |t|
                  t.string   :scope_type,         null: false
                  t.bigint   :scope_id,           null: false
                  t.string   :extractor_revision, null: false
                  t.datetime :computed_at,        null: false
                  t.float    :size_compliance
                  t.float    :intrachunk_cohesion
                  t.float    :document_contextual_coherence
                  t.float    :block_integrity
                  t.float    :references_completeness
                  t.timestamps
                end
                add_index :vv_memory_conformer_quality,
                          [:scope_type, :scope_id, :extractor_revision, :computed_at],
                          name: "index_vv_memory_conformer_quality_lookup"
              end
            end

            unless conn.table_exists?(:sessions)
              ::ActiveRecord::Schema.define do
                create_table :sessions do |t|
                  t.string :name
                  t.timestamps
                end
              end
            end

            # PLAN_0_1_0 Phase B — the Decision aggregate table.
            # Mirror of db/migrate/20260525000001.
            unless conn.table_exists?(:vv_decision_decisions)
              ::ActiveRecord::Schema.define do
                create_table :vv_decision_decisions do |t|
                  t.references :scope, polymorphic: true, null: false, index: true
                  t.string   :context,        null: false
                  t.string   :decided_option, null: true
                  t.text     :because
                  t.json     :alternatives,      null: false, default: []
                  t.json     :reasoning_payload, null: false, default: {}
                  t.bigint   :decision_context_episode_id
                  t.bigint   :decision_outcome_episode_id
                  t.datetime :decided_at, null: true
                  t.string   :provenance_id
                  t.timestamps
                end
                add_index :vv_decision_decisions, :decided_at
                add_index :vv_decision_decisions, [:scope_type, :scope_id, :decided_at]
                add_index :vv_decision_decisions, :provenance_id,
                          unique: true, where: "provenance_id IS NOT NULL"
              end
            end
          end

          def reset!
            conn = ::ActiveRecord::Base.connection
            %i[
              vv_decision_decisions
              vv_memory_episodes
              vv_memory_conformer_cursors
              vv_memory_conformer_quality
              sessions
            ].each do |table|
              conn.execute("DELETE FROM #{table}") if conn.table_exists?(table)
            end
          end
        end
      end
    end
  end
end
