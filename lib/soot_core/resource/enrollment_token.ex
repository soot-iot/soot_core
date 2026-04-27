defmodule SootCore.Resource.EnrollmentToken do
  @moduledoc """
  `Ash.Resource` extension that injects the `SootCore` enrollment-token
  schema (attributes, identity, mint / consume / find_active actions, and
  the standard code interface) into a consumer-owned resource module.

  Tokens are stored hashed; the plaintext is returned exactly once on
  the result of `mint/3` via Ash resource metadata. Replay protection:
  `consume/1` validates `used_at` is `nil` before stamping it.

  Usage and override semantics mirror `SootCore.Resource.Tenant`. Register
  via `config :soot_core, enrollment_token: MyApp.EnrollmentToken`.
  """

  use Spark.Dsl.Extension,
    transformers: [SootCore.Resource.EnrollmentToken.Transformers.Inject]
end
