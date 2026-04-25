defmodule SootCore.EnrollmentTokenTest do
  use ExUnit.Case, async: false

  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    %{tenant: t} = Factories.fresh_tenant!("acme")
    {:ok, dev} = SootCore.Device.create_unprovisioned(t.id, "S1")
    {:ok, tenant: t, device: dev}
  end

  test "mint returns plaintext via __metadata__ once", %{tenant: t, device: d} do
    {:ok, et, plaintext} = Factories.mint_token(t.id, d.id)
    assert is_binary(plaintext)
    assert String.length(plaintext) > 30
    refute et.token_hash == plaintext

    {:ok, found} = SootCore.EnrollmentToken.find_active(plaintext)
    assert found.id == et.id
  end

  test "consume marks token used; replay errors", %{tenant: t, device: d} do
    {:ok, et, _plaintext} = Factories.mint_token(t.id, d.id)

    {:ok, consumed} = SootCore.EnrollmentToken.consume(et)
    assert consumed.used_at

    assert {:error, _} = SootCore.EnrollmentToken.consume(consumed)
  end

  test "find_active rejects used or expired tokens", %{tenant: t, device: d} do
    {:ok, _et, plaintext} = Factories.mint_token(t.id, d.id, -10)
    assert {:error, _} = SootCore.EnrollmentToken.find_active(plaintext)
  end
end
