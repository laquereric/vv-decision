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

# Phase B / C / D / E surfaces (Decision AR model, DeliberationContext,
# DecisionExtractor, traversal methods) require this loader. They
# are pulled in as those phases land.
