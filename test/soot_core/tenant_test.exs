defmodule SootCore.TenantTest do
  use ExUnit.Case, async: false

  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    :ok
  end

  test "slug must match the public-facing pattern" do
    assert {:error, _} = SootCore.Tenant.create("Acme Inc!", "Acme")
    assert {:error, _} = SootCore.Tenant.create("a", "Too short")
    assert {:error, _} = SootCore.Tenant.create("UPPERCASE", "No caps")
    assert {:ok, _} = SootCore.Tenant.create("acme-eu", "Acme EU")
  end

  test "slug is unique" do
    assert {:ok, _} = SootCore.Tenant.create("acme", "Acme")
    assert {:error, _} = SootCore.Tenant.create("acme", "Other")
  end

  test "lifecycle transitions" do
    {:ok, t} = SootCore.Tenant.create("acme", "Acme")
    assert t.status == :active

    {:ok, t} = SootCore.Tenant.suspend(t)
    assert t.status == :suspended

    {:ok, t} = SootCore.Tenant.reactivate(t)
    assert t.status == :active

    {:ok, t} = SootCore.Tenant.archive(t)
    assert t.status == :archived
  end
end
