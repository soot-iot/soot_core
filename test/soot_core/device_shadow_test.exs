defmodule SootCore.DeviceShadowTest do
  use ExUnit.Case, async: false

  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    %{tenant: t} = Factories.fresh_tenant!("acme")

    {:ok, dev} =
      SootCore.Device.create_unprovisioned(t.id, "ACME-EU-WIDGET-0001-000001", authorize?: false)

    {:ok, tenant: t, device: dev}
  end

  test "create initialises with empty desired/reported and version 0", %{device: d} do
    {:ok, shadow} = SootCore.DeviceShadow.create(d.id, authorize?: false)
    assert shadow.desired == %{}
    assert shadow.reported == %{}
    assert shadow.version == 0
    assert is_nil(shadow.last_reported_at)
  end

  test "update_desired bumps the version and stores the new map", %{device: d} do
    {:ok, shadow} = SootCore.DeviceShadow.create(d.id, authorize?: false)

    {:ok, updated} =
      SootCore.DeviceShadow.update_desired(shadow, %{"led" => "on"}, authorize?: false)

    assert updated.desired == %{"led" => "on"}
    assert updated.version == 1
    assert is_nil(updated.last_reported_at)
  end

  test "update_reported bumps the version, sets last_reported_at, stores reported map", %{
    device: d
  } do
    {:ok, shadow} = SootCore.DeviceShadow.create(d.id, authorize?: false)

    before = DateTime.utc_now()

    {:ok, updated} =
      SootCore.DeviceShadow.update_reported(shadow, %{"led" => "off"}, authorize?: false)

    assert updated.reported == %{"led" => "off"}
    assert updated.version == 1
    assert %DateTime{} = updated.last_reported_at
    assert DateTime.compare(updated.last_reported_at, before) in [:gt, :eq]
  end

  test "version increments across multiple updates", %{device: d} do
    {:ok, shadow} = SootCore.DeviceShadow.create(d.id, authorize?: false)
    {:ok, s1} = SootCore.DeviceShadow.update_desired(shadow, %{"a" => 1}, authorize?: false)
    {:ok, s2} = SootCore.DeviceShadow.update_reported(s1, %{"a" => 1}, authorize?: false)
    {:ok, s3} = SootCore.DeviceShadow.update_desired(s2, %{"a" => 2}, authorize?: false)

    assert [s1.version, s2.version, s3.version] == [1, 2, 3]
  end

  test "for_device fetches the row for that device", %{device: d} do
    {:ok, shadow} = SootCore.DeviceShadow.create(d.id, authorize?: false)
    assert {:ok, found} = SootCore.DeviceShadow.for_device(d.id, authorize?: false)
    assert found.id == shadow.id
  end

  test "for_device on an unknown device id returns NotFound" do
    other_id = Ecto.UUID.generate()

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} =
             SootCore.DeviceShadow.for_device(other_id, authorize?: false)
  end

  test "one_per_device identity blocks a second shadow row for the same device", %{device: d} do
    assert {:ok, _} = SootCore.DeviceShadow.create(d.id, authorize?: false)
    assert {:error, _} = SootCore.DeviceShadow.create(d.id, authorize?: false)
  end
end
