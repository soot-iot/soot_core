defmodule SootCore.DeviceTest do
  use ExUnit.Case, async: false

  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    %{tenant: t} = Factories.fresh_tenant!("acme")
    {:ok, tenant: t}
  end

  test "fresh device starts in :unprovisioned", %{tenant: t} do
    {:ok, dev} = SootCore.Device.create_unprovisioned(t.id, "ACME-EU-WIDGET-0001-000001")
    assert dev.state == :unprovisioned
  end

  test "transitions follow the spec graph", %{tenant: t} do
    {:ok, dev} = SootCore.Device.create_unprovisioned(t.id, "S1")
    cert_id = Ecto.UUID.generate()

    {:ok, dev} = SootCore.Device.bootstrap(dev, cert_id)
    assert dev.state == :bootstrapped

    {:ok, dev} = SootCore.Device.enroll(dev, Ecto.UUID.generate())
    assert dev.state == :operational

    {:ok, dev} = SootCore.Device.quarantine(dev)
    assert dev.state == :quarantined

    {:ok, dev} = SootCore.Device.unquarantine(dev)
    assert dev.state == :operational

    {:ok, dev} = SootCore.Device.retire(dev)
    assert dev.state == :retired
  end

  test "invalid transitions are rejected", %{tenant: t} do
    {:ok, dev} = SootCore.Device.create_unprovisioned(t.id, "S2")

    # Skip bootstrapped
    assert {:error, _} = SootCore.Device.enroll(dev, Ecto.UUID.generate())

    # Retired is terminal
    {:ok, dev} = SootCore.Device.bootstrap(dev, Ecto.UUID.generate())
    {:ok, dev} = SootCore.Device.enroll(dev, Ecto.UUID.generate())
    {:ok, dev} = SootCore.Device.retire(dev)
    assert {:error, _} = SootCore.Device.unquarantine(dev)
    assert {:error, _} = SootCore.Device.bootstrap(dev, Ecto.UUID.generate())
  end

  test "serials are unique per tenant but reusable across tenants", %{tenant: t1} do
    %{tenant: t2} = Factories.fresh_tenant!("beta")

    assert {:ok, _} = SootCore.Device.create_unprovisioned(t1.id, "SHARED-SERIAL")
    assert {:error, _} = SootCore.Device.create_unprovisioned(t1.id, "SHARED-SERIAL")
    assert {:ok, _} = SootCore.Device.create_unprovisioned(t2.id, "SHARED-SERIAL")
  end
end
