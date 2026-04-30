defmodule SootCore.Actors do
  @moduledoc """
  Actor factory for `soot_core`.

  Three kinds of actor flow into Ash policy evaluation:

    * `Device` — the `SootCore.Device` (or operator override) row of a
      connected, enrolled fleet member. Cert verification produces
      this actor; policies that scope by device ownership pattern-match
      on the Device struct.

    * `System` — an internal subsystem with no end-user, scoped by a
      `:part` atom describing what it is doing (`:enroller`,
      `:registry_sync`, `:crl_publisher`, ...). Library code that
      previously passed `authorize?: false` now passes a `System`
      actor so policies can reason about it.

    * `User` — admin actors produced by `ash_authentication`. Pass
      through as-is; this module is the conventional entry point so
      operator code reads uniformly.

  Operator apps generate their own `MyApp.Actors` module via
  `mix soot.install`. Library code looks up the configured actor
  module (defaulting to this one) so an operator can extend the
  System part list, customize `device/1` to load operator overrides,
  etc. This module is the soot_core default and what tests use.

  See `POLICY-SPEC.md` for the full actor contract and per-resource
  policy matrix.
  """

  alias SootCore.Actors.System

  @type system_part :: System.part()
  @type t :: System.t() | struct()

  @doc """
  Build a `System` actor for an internal subsystem.

  `part` enumerates which subsystem; pass `tenant_id` when the
  subsystem operates against a specific tenant (e.g. an enrollment
  flow scoped to one tenant's CA).
  """
  @spec system(system_part()) :: System.t()
  def system(part) when is_atom(part), do: %System{part: part}

  @spec system(system_part(), keyword() | binary() | nil) :: System.t()
  def system(part, tenant_id) when is_atom(part) and is_binary(tenant_id),
    do: %System{part: part, tenant_id: tenant_id}

  def system(part, nil) when is_atom(part), do: %System{part: part}

  def system(part, opts) when is_atom(part) and is_list(opts),
    do: %System{part: part, tenant_id: Keyword.get(opts, :tenant_id)}

  @doc """
  Pass-through for a Device-as-actor.

  Library code calls `SootCore.actors().device(device)` so operator
  overrides can wrap the resource in something richer (e.g. preload
  associations) without library code knowing the concrete module.
  """
  @spec device(struct()) :: struct()
  def device(%_{} = device), do: device

  @doc """
  Pass-through for a User actor (typically an `ash_authentication`
  resource row). Identity by default; operators can override to
  enrich (preload roles, etc.).
  """
  @spec user(struct()) :: struct()
  def user(%_{} = user), do: user

  @doc """
  Build a stand-in admin actor for tests.

  In a generated app the admin actor is a `MyApp.Accounts.User` row
  with `role: :admin` and the user's `tenant_id`. Library tests don't
  have that resource, so this helper fabricates a plain struct with
  the same shape — `Ash.Policy.Authorizer` only reads `:role` and
  `:tenant_id` off the actor, so the struct module doesn't matter.
  """
  @spec admin(binary()) :: %{role: :admin, tenant_id: binary()}
  def admin(tenant_id) when is_binary(tenant_id),
    do: %{role: :admin, tenant_id: tenant_id}
end
