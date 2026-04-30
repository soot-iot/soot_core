defmodule SootCore.Actors.System do
  @moduledoc """
  Internal-subsystem actor.

  `:part` is a closed atom describing what subsystem is acting. Each
  library that originates a System actor enumerates the parts it uses
  (see `POLICY-SPEC.md` §3.2). Resource policies match on `:part` to
  decide which internal flows are allowed.

  `:tenant_id` is set when the subsystem operates against a specific
  tenant; nil for cross-tenant flows like CRL publishing or trust-
  anchor loading.

  `:seed` is the setup-context part: `mix soot.demo.seed` and similar
  one-shot bootstrap tasks construct rows across every soot_core
  resource and need a single actor that satisfies each resource's
  policy. Treat it as the System equivalent of `authorize?: false`
  in `test/support/factories.ex` — sanctioned, but only from setup
  scripts, not request paths.

  Operators may add their own parts in `MyApp.Actors`. The struct
  itself is library-defined so policies that pattern-match on
  `actor_attribute_equals(:__struct__, SootCore.Actors.System)` work
  consistently across libraries.
  """

  @enforce_keys [:part]
  defstruct [:part, :tenant_id]

  @type part ::
          :enroller
          | :batch_provisioner
          | :crl_publisher
          | :issuer
          | :trust_loader
          | :mtls_resolver
          | :registry_sync
          | :publisher
          | :metric_monitor
          | :device_shadow_writer
          | :seed

  @type t :: %__MODULE__{
          part: part(),
          tenant_id: String.t() | nil
        }
end
