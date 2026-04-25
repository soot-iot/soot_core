defmodule SootCore.ProductionBatchTest do
  use ExUnit.Case, async: false

  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    %{tenant: tenant} = Factories.fresh_tenant!("acme")
    scheme = Factories.fresh_scheme!(tenant.id, prefix: "ACME-EU-WIDGET")
    batch = Factories.fresh_batch!(tenant.id, scheme.id, code: "2026-W17-A")
    {:ok, tenant: tenant, scheme: scheme, batch: batch}
  end

  test "import_csv creates one device per valid row", %{tenant: t, batch: b} do
    csv = """
    serial,model,metadata
    ACME-EU-WIDGET-0001-000001,widget-v2,
    ACME-EU-WIDGET-0001-000002,widget-v2,
    ACME-EU-WIDGET-0001-000003,widget-v2,
    """

    assert {:ok, %{inserted: 3, errors: []}} =
             SootCore.ProductionBatch.import_csv(b.id, csv)

    {:ok, devices} = SootCore.Device.for_tenant(t.id)
    assert length(devices) == 3
    assert Enum.all?(devices, &(&1.state == :unprovisioned))
    assert Enum.all?(devices, &(&1.batch_id == b.id))
  end

  test "import_csv skips rows that fail serial validation", %{batch: b} do
    csv = """
    serial,model
    ACME-EU-WIDGET-0001-000001,ok
    NOT-A-VALID-SERIAL,bad
    ACME-EU-WIDGET-0001-000002,ok
    """

    assert {:ok, %{inserted: 2, errors: [{3, _reason}]}} =
             SootCore.ProductionBatch.import_csv(b.id, csv)
  end

  test "import_csv parses metadata json column", %{tenant: t, batch: b} do
    # NimbleCSV's default escape doesn't allow embedded quotes in unquoted
    # fields; use a value without quotes for this test.
    csv = """
    serial,model,metadata
    ACME-EU-WIDGET-0001-000001,widget-v2,{}
    """

    assert {:ok, %{inserted: 1, errors: []}} =
             SootCore.ProductionBatch.import_csv(b.id, csv)

    {:ok, [dev]} = SootCore.Device.for_tenant(t.id)
    assert dev.metadata == %{}
  end
end
