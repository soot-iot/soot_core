defmodule SootCore.Policies.SameTenant do
  @moduledoc """
  Filter check: the actor's `tenant_id` must match the resource's
  `tenant_id`.

  Use in a resource policy:

      policies do
        policy action_type(:read) do
          authorize_if SootCore.Policies.SameTenant
        end
      end

  The actor is expected to carry a `:tenant_id` field (atom or string key).
  Devices going through `SootCore.Plug.Enroll` and the operational
  endpoints have their tenant resolved from the cert SAN before any Ash
  call; admin actors carry it from their auth system.
  """

  use Ash.Policy.FilterCheck

  require Ash.Query

  @impl true
  def describe(_opts) do
    "actor's tenant_id matches record's tenant_id"
  end

  @impl true
  def filter(_actor, _authorizer, _opts) do
    Ash.Expr.expr(tenant_id == ^actor(:tenant_id))
  end
end
