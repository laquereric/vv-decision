# frozen_string_literal: true

# PLAN_0_1_0 Phase B — the Decision aggregate root.
#
# One row per `Vv::Decision.deliberate(...)` call. Polymorphic
# scope mirrors `Vv::Memory::Episode`'s `(scope_type, scope_id)`
# shape so the two tables join cleanly. Two FK columns reference
# `vv_memory_episodes.id` (the context + outcome flow episodes) —
# this relies on vv-memory's pinned `vv_memory_episodes` table +
# bigint `id` PK (vv-memory STABILITY.md, CR_DS B5).
#
# `alternatives` / `reasoning_payload` use the `json` column type
# (TEXT-backed on SQLite, native json on PostgreSQL — AR casts to
# Ruby Hash/Array on read either way). PostgreSQL operators may
# `ALTER` them to `jsonb` post-bundle for query-side ergonomics;
# the on-disk shape is JSON regardless.
class CreateVvDecisionDecisions < ActiveRecord::Migration[7.1]
  def change
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
              unique: true,
              where: "provenance_id IS NOT NULL"
    add_foreign_key :vv_decision_decisions, :vv_memory_episodes,
                    column: :decision_context_episode_id
    add_foreign_key :vv_decision_decisions, :vv_memory_episodes,
                    column: :decision_outcome_episode_id
  end
end
