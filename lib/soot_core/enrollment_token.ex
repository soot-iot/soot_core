defmodule SootCore.EnrollmentToken do
  @moduledoc """
  Default `EnrollmentToken` resource shipped with `soot_core`.

  Single-use bootstrap credential, scoped to a single device.

  The token plaintext is shown exactly once at mint time via
  `Ash.Resource.get_metadata(record, :plaintext_token)`. The DB stores
  only the SHA-256 hash. Replay protection: `consume/1` verifies the
  token has not yet been used and stamps `used_at` atomically.

  This resource is the IoT-flavored counterpart of
  `AshPki.EnrollmentToken`; the two intentionally do not share code (the
  PKI bootstrap-cert workflow and the device-row enrollment workflow are
  different lifecycles).

  The schema is provided by the `SootCore.Resource.EnrollmentToken`
  extension. This default uses `Ash.DataLayer.Ets`; production deployments
  override with their own resource module backed by `AshPostgres.DataLayer`
  and register it via `config :soot_core, enrollment_token:
  MyApp.EnrollmentToken`.
  """

  use Ash.Resource,
    otp_app: :soot_core,
    domain: SootCore.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [SootCore.Resource.EnrollmentToken]

  ets do
    private? false
  end

  # Default policies (POLICY-SPEC §4.1).
  policies do
    policy always() do
      access_type :strict
      authorize_if actor_attribute_equals(:part, :enroller)
      authorize_if actor_attribute_equals(:part, :batch_provisioner)
    end
  end
end
