defmodule SootCore.Device do
  @moduledoc """
  Default `Device` resource shipped with `soot_core`.

  A unit in the fleet.

  States (driven by `AshStateMachine`):

      unprovisioned → bootstrapped → operational ⇄ quarantined
                                          ↓
                                       retired

  - `unprovisioned`: row exists, no cert.
  - `bootstrapped`: bootstrap cert issued; the device may only call `/enroll`.
  - `operational`: operational cert in hand; full telemetry/command rights.
  - `quarantined`: a fast kill switch (policies refuse the device); cert
    not yet revoked.
  - `retired`: end-of-life; cert revoked, row retained for audit.

  The schema (attributes, identities, relationships, lifecycle actions) is
  provided by the `SootCore.Resource.Device` extension. This default uses
  `Ash.DataLayer.Ets` so the library's own tests, demos, and smoke tasks
  run without a Postgres dependency. Production deployments declare their
  own resource module backed by `AshPostgres.DataLayer` and register it
  via `config :soot_core, device: MyApp.Device` — see
  `SootCore.Resource.Device` for the full pattern.
  """

  use Ash.Resource,
    otp_app: :soot_core,
    domain: SootCore.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, SootCore.Resource.Device]

  ets do
    private? false
  end

  state_machine do
    initial_states [:unprovisioned]
    default_initial_state :unprovisioned

    transitions do
      transition :bootstrap, from: :unprovisioned, to: :bootstrapped
      transition :enroll, from: :bootstrapped, to: :operational
      transition :quarantine, from: [:operational, :bootstrapped], to: :quarantined
      transition :unquarantine, from: :quarantined, to: :operational
      transition :retire, from: [:operational, :quarantined, :bootstrapped], to: :retired
    end
  end

  # Default policies (POLICY-SPEC §4.1).
  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if SootCore.Policies.SameTenant
    end

    policy always() do
      access_type :strict
      authorize_if actor_attribute_equals(:part, :enroller)
      authorize_if actor_attribute_equals(:part, :batch_provisioner)
      authorize_if actor_attribute_equals(:part, :mtls_resolver)
      authorize_if actor_attribute_equals(:part, :seed)
    end
  end
end
