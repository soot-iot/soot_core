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

  test "get_by_slug returns the tenant; missing slug → NotFound" do
    {:ok, t} = SootCore.Tenant.create("acme", "Acme")
    assert {:ok, found} = SootCore.Tenant.get_by_slug("acme")
    assert found.id == t.id

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} =
             SootCore.Tenant.get_by_slug("nope")
  end

  test "create accepts issuing_ca_id and metadata" do
    fake_ca_id = Ecto.UUID.generate()
    {:ok, t} = SootCore.Tenant.create("acme", "Acme", %{issuing_ca_id: fake_ca_id, metadata: %{"region" => "eu"}})

    assert t.issuing_ca_id == fake_ca_id
    assert t.metadata == %{"region" => "eu"}
  end
end
