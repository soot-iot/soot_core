defmodule SootCore.Policies.OwnTenant do
  @moduledoc """
  Filter check: the resource's `id` must equal the actor's `tenant_id`.

  Use this on the `Tenant` resource itself, where the row's primary key
  is the tenant id (there is no separate `tenant_id` column). For every
  other resource — Device, DeviceShadow, EnrollmentToken, etc. — use
  `SootCore.Policies.SameTenant` instead.

      policies do
        policy actor_attribute_equals(:role, :admin) do
          authorize_if SootCore.Policies.OwnTenant
        end
      end
  """

  use Ash.Policy.FilterCheck

  require Ash.Query

  @impl true
  def describe(_opts) do
    "tenant id matches actor's tenant_id"
  end

  @impl true
  def filter(_actor, _authorizer, _opts) do
    Ash.Expr.expr(id == ^actor(:tenant_id))
  end
end
