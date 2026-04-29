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
             SootCore.ProductionBatch.import_csv(b.id, csv, authorize?: false)

    {:ok, devices} = SootCore.Device.for_tenant(t.id, authorize?: false)
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
             SootCore.ProductionBatch.import_csv(b.id, csv, authorize?: false)
  end

  test "import_csv parses metadata json column", %{tenant: t, batch: b} do
    # Fields containing commas or quotes must be CSV-escaped. Use NimbleCSV's
    # standard double-quote escaping for the JSON value.
    csv =
      "serial,model,metadata\n" <>
        ~s(ACME-EU-WIDGET-0001-000001,widget-v2,"{""line"":""A""}") <> "\n"

    assert {:ok, %{inserted: 1, errors: []}} =
             SootCore.ProductionBatch.import_csv(b.id, csv, authorize?: false)

    {:ok, [dev]} = SootCore.Device.for_tenant(t.id, authorize?: false)
    assert dev.metadata == %{"line" => "A"}
  end

  test "import_csv applies default_model when model column is absent", %{tenant: t, batch: b} do
    csv = """
    serial
    ACME-EU-WIDGET-0001-000001
    """

    assert {:ok, %{inserted: 1, errors: []}} =
             SootCore.ProductionBatch.import_csv(b.id, csv,
               default_model: "fallback-model",
               authorize?: false
             )

    {:ok, [dev]} = SootCore.Device.for_tenant(t.id, authorize?: false)
    assert dev.model == "fallback-model"
  end

  test "unique_code_per_tenant rejects duplicates within a tenant", %{tenant: t, scheme: s} do
    Factories.fresh_batch!(t.id, s.id, code: "DUP")
    assert {:error, _} = SootCore.ProductionBatch.create(t.id, s.id, "DUP", authorize?: false)
  end

  test "unique_code_per_tenant allows the same code across tenants", %{batch: b, scheme: s} do
    %{tenant: t2} = Factories.fresh_tenant!("beta")
    s2 = Factories.fresh_scheme!(t2.id, prefix: "BETA")
    assert {:ok, _} = SootCore.ProductionBatch.create(t2.id, s2.id, b.code, authorize?: false)
    _ = s
  end

  test "close transitions status to :closed", %{batch: b} do
    assert b.status == :open
    {:ok, closed} = SootCore.ProductionBatch.close(b, authorize?: false)
    assert closed.status == :closed
  end

  test "for_tenant scopes the listing", %{tenant: t1, batch: b1} do
    %{tenant: t2} = Factories.fresh_tenant!("beta")
    s2 = Factories.fresh_scheme!(t2.id, prefix: "BETA")
    Factories.fresh_batch!(t2.id, s2.id, code: "OTHER")

    {:ok, batches} = SootCore.ProductionBatch.for_tenant(t1.id, authorize?: false)
    assert Enum.map(batches, & &1.id) == [b1.id]
  end
end
