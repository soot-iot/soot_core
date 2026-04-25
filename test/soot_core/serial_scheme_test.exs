defmodule SootCore.SerialSchemeTest do
  use ExUnit.Case, async: false

  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    %{tenant: tenant} = Factories.fresh_tenant!("acme")
    {:ok, tenant: tenant}
  end

  test "generate/parse roundtrip without check digit", %{tenant: t} do
    scheme = Factories.fresh_scheme!(t.id, prefix: "ACME-EU-WIDGET")
    serial = SootCore.SerialScheme.generate!(scheme, 42, 7)

    assert serial == "ACME-EU-WIDGET-0042-000007"
    assert {:ok, %{batch: 42, sequence: 7}} = SootCore.SerialScheme.parse(scheme, serial)
  end

  test "generate appends a Luhn check digit", %{tenant: t} do
    scheme = Factories.fresh_scheme!(t.id, prefix: "ACME-EU-WIDGET", check_digit: :luhn)
    serial = SootCore.SerialScheme.generate!(scheme, 42, 1)

    assert :ok = SootCore.SerialScheme.validate(scheme, serial)
    assert {:error, :invalid_check_digit} =
             SootCore.SerialScheme.validate(scheme, "ACME-EU-WIDGET-0042-000001-9")
  end

  test "validate rejects malformed input", %{tenant: t} do
    scheme = Factories.fresh_scheme!(t.id, prefix: "ACME-EU-WIDGET")

    assert {:error, :prefix_mismatch} = SootCore.SerialScheme.validate(scheme, "OTHER-0001-000001")
    assert {:error, :wrong_part_count} = SootCore.SerialScheme.validate(scheme, "ACME-EU-WIDGET-0001")
    assert {:error, :invalid_numeric_component} =
             SootCore.SerialScheme.validate(scheme, "ACME-EU-WIDGET-XXXX-000001")
  end

  test "generate refuses to overflow widths", %{tenant: t} do
    scheme = Factories.fresh_scheme!(t.id, prefix: "ACME")
    assert {:error, :batch_overflow} = SootCore.SerialScheme.generate(scheme, 99_999, 1)
    assert {:error, :sequence_overflow} = SootCore.SerialScheme.generate(scheme, 1, 9_999_999)
  end
end
