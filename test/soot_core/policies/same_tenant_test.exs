defmodule SootCore.Policies.SameTenantTest do
  use ExUnit.Case, async: false

  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    %{tenant: a} = Factories.fresh_tenant!("alpha")
    %{tenant: b} = Factories.fresh_tenant!("beta")
    {:ok, da} = SootCore.Device.create_unprovisioned(a.id, "ALPHA-DEV-1", authorize?: false)
    {:ok, db} = SootCore.Device.create_unprovisioned(b.id, "BETA-DEV-1", authorize?: false)
    {:ok, alpha: a, beta: b, alpha_device: da, beta_device: db}
  end

  test "filter expression scopes a query to the actor's tenant", %{
    alpha: a,
    alpha_device: da,
    beta_device: db
  } do
    require Ash.Query

    actor = %{tenant_id: a.id}

    {:ok, results} =
      SootCore.Device
      |> Ash.Query.filter(tenant_id == ^a.id)
      |> Ash.read(actor: actor, authorize?: false)

    ids = Enum.map(results, & &1.id)
    assert da.id in ids
    refute db.id in ids
  end

  test "filter/3 returns an Ash expression usable in policies", %{alpha: a} do
    actor = %{tenant_id: a.id}
    expr = SootCore.Policies.SameTenant.filter(actor, nil, [])
    refute is_nil(expr)
  end

  test "describe/1 returns a non-empty human-readable string" do
    assert is_binary(SootCore.Policies.SameTenant.describe([]))
    assert String.length(SootCore.Policies.SameTenant.describe([])) > 0
  end
end
