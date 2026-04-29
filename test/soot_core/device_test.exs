defmodule SootCore.DeviceTest do
  use ExUnit.Case, async: false

  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    %{tenant: t} = Factories.fresh_tenant!("acme")
    {:ok, tenant: t}
  end

  test "fresh device starts in :unprovisioned", %{tenant: t} do
    {:ok, dev} =
      SootCore.Device.create_unprovisioned(t.id, "ACME-EU-WIDGET-0001-000001", authorize?: false)

    assert dev.state == :unprovisioned
  end

  test "transitions follow the spec graph", %{tenant: t} do
    {:ok, dev} = SootCore.Device.create_unprovisioned(t.id, "S1", authorize?: false)
    cert_id = Ecto.UUID.generate()

    {:ok, dev} = SootCore.Device.bootstrap(dev, cert_id, authorize?: false)
    assert dev.state == :bootstrapped

    {:ok, dev} = SootCore.Device.enroll(dev, Ecto.UUID.generate(), authorize?: false)
    assert dev.state == :operational

    {:ok, dev} = SootCore.Device.quarantine(dev, authorize?: false)
    assert dev.state == :quarantined

    {:ok, dev} = SootCore.Device.unquarantine(dev, authorize?: false)
    assert dev.state == :operational

    {:ok, dev} = SootCore.Device.retire(dev, authorize?: false)
    assert dev.state == :retired
  end

  test "invalid transitions are rejected", %{tenant: t} do
    {:ok, dev} = SootCore.Device.create_unprovisioned(t.id, "S2", authorize?: false)

    # Skip bootstrapped
    assert {:error, _} = SootCore.Device.enroll(dev, Ecto.UUID.generate(), authorize?: false)

    # Retired is terminal
    {:ok, dev} = SootCore.Device.bootstrap(dev, Ecto.UUID.generate(), authorize?: false)
    {:ok, dev} = SootCore.Device.enroll(dev, Ecto.UUID.generate(), authorize?: false)
    {:ok, dev} = SootCore.Device.retire(dev, authorize?: false)
    assert {:error, _} = SootCore.Device.unquarantine(dev, authorize?: false)
    assert {:error, _} = SootCore.Device.bootstrap(dev, Ecto.UUID.generate(), authorize?: false)
  end

  test "serials are unique per tenant but reusable across tenants", %{tenant: t1} do
    %{tenant: t2} = Factories.fresh_tenant!("beta")

    assert {:ok, _} =
             SootCore.Device.create_unprovisioned(t1.id, "SHARED-SERIAL", authorize?: false)

    assert {:error, _} =
             SootCore.Device.create_unprovisioned(t1.id, "SHARED-SERIAL", authorize?: false)

    assert {:ok, _} =
             SootCore.Device.create_unprovisioned(t2.id, "SHARED-SERIAL", authorize?: false)
  end

  test "touch stamps last_seen_at", %{tenant: t} do
    {:ok, dev} = SootCore.Device.create_unprovisioned(t.id, "TOUCH-SERIAL", authorize?: false)
    assert is_nil(dev.last_seen_at)

    before = DateTime.utc_now()
    {:ok, dev} = SootCore.Device.touch(dev, authorize?: false)

    assert %DateTime{} = dev.last_seen_at
    assert DateTime.compare(dev.last_seen_at, before) in [:gt, :eq]
  end

  test "get_by_serial scopes to tenant", %{tenant: t1} do
    %{tenant: t2} = Factories.fresh_tenant!("beta")

    {:ok, d1} = SootCore.Device.create_unprovisioned(t1.id, "DUPE", authorize?: false)
    {:ok, _d2} = SootCore.Device.create_unprovisioned(t2.id, "DUPE", authorize?: false)

    {:ok, found} = SootCore.Device.get_by_serial(t1.id, "DUPE", authorize?: false)
    assert found.id == d1.id

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} =
             SootCore.Device.get_by_serial(t1.id, "MISSING", authorize?: false)
  end

  test "for_tenant lists only the tenant's devices", %{tenant: t1} do
    %{tenant: t2} = Factories.fresh_tenant!("beta")

    {:ok, _} = SootCore.Device.create_unprovisioned(t1.id, "T1-A", authorize?: false)
    {:ok, _} = SootCore.Device.create_unprovisioned(t1.id, "T1-B", authorize?: false)
    {:ok, _} = SootCore.Device.create_unprovisioned(t2.id, "T2-A", authorize?: false)

    {:ok, devices} = SootCore.Device.for_tenant(t1.id, authorize?: false)
    assert length(devices) == 2
    assert Enum.all?(devices, &(&1.tenant_id == t1.id))
  end
end
