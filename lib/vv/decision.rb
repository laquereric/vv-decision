# frozen_string_literal: true

require "vv/decision/version"
require "vv/decision/errors"

# The vv-memory dependency. We require it eagerly so the
# `MissingDependency` guard in `Engine` can speak to a definite
# state — present, or refused with a verbatim hint.
begin
  require "vv/memory"
rescue LoadError
  # Surface the failure mode at boot, not at first call. The
  # Engine's `after_initialize` block performs the final check;
  # consumers running outside Rails get the same hint via the
  # constant-presence check on `Vv::Memory::Scoped` +
  # `Vv::Memory::Conformer::Extractor`.
end

# Rails-app context bootstraps the Engine + AR model.
if defined?(::Rails::Engine)
  require "vv/decision/engine"
end

# Phase B — the Decision AR aggregate root lives under `app/models/`
# (Engine autoloads in a Rails host; spec contexts add `app/models`
# to LOAD_PATH so the require resolves there). Guarded like
# vv-memory's `Vv::Memory::Episode` require.
if defined?(::ActiveRecord)
  begin
    require "vv/decision/decision"
  rescue LoadError
    # Only fails when loaded without app/models on LOAD_PATH and
    # without a Rails engine. Defer to first use.
  end
end

# Phase C — the forward-acting entrypoint + flow context. Pure-Ruby
# orchestration over `Vv::Memory::Scoped`; safe to require eagerly.
require "vv/decision/evidence_slice"
require "vv/decision/deliberation_context"
require "vv/decision/deliberate"

# Phase D — the Conformer extractor that promotes decision_outcome
# Bronze episodes into vvdec: Silver triples. Required eagerly (it
# self-loads its `Vv::Memory::Conformer::Extractor` base class). The
# Engine's after_initialize calls `Vv::Decision.register_extractor!`
# to bind it to the "decision_outcome" kind in vv-memory's registry.
require "vv/decision/decision_extractor"
