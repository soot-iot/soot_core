defmodule SootCore.Plug.EnrollTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias AshPki.Plug.MTLS
  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    ctx = Factories.fresh_tenant!("acme")
    serial = "ACME-EU-WIDGET-0001-000001"
    bootstrap = Factories.bootstrapped_device!(ctx, serial)
    {:ok, Map.merge(ctx, bootstrap)}
  end

  defp run_enroll(bootstrap_cert, body) do
    pem = bootstrap_cert.certificate_pem

    conn(:post, "/enroll", Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-client-cert", URI.encode(pem, &URI.char_unreserved?/1))
    |> MTLS.call(MTLS.init(header_mode: {:enabled, "x-client-cert"}, require_known_certificate: true))
    |> SootCore.Plug.Enroll.call([])
  end

  defp issue_csr_pem do
    priv = X509.PrivateKey.new_ec(:secp256r1)
    csr = X509.CSR.new(priv, "/CN=device-operational")
    {priv, X509.CSR.to_pem(csr)}
  end

  test "happy path: token + CSR yields operational cert and transitions device", ctx do
    {_priv, csr_pem} = issue_csr_pem()

    conn =
      run_enroll(ctx.bootstrap_certificate, %{
        "token" => ctx.plaintext_token,
        "csr_pem" => csr_pem
      })

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["state"] == "operational"
    assert String.starts_with?(body["certificate_pem"], "-----BEGIN CERTIFICATE-----")
    assert String.contains?(body["chain_pem"], "-----BEGIN CERTIFICATE-----")

    {:ok, device} = Ash.get(SootCore.Device, ctx.device.id, authorize?: false)
    assert device.state == :operational
    refute is_nil(device.operational_certificate_id)

    {:ok, et} = Ash.get(SootCore.EnrollmentToken, ctx.enrollment_token.id, authorize?: false)
    refute is_nil(et.used_at)
  end

  test "token replay is rejected", ctx do
    {_priv, csr_pem} = issue_csr_pem()

    body = %{"token" => ctx.plaintext_token, "csr_pem" => csr_pem}
    assert run_enroll(ctx.bootstrap_certificate, body).status == 200

    second = run_enroll(ctx.bootstrap_certificate, body)
    assert second.status in [403, 409]
  end

  test "token bound to another device is rejected", ctx do
    other_serial = "ACME-EU-WIDGET-0001-000002"
    other = Factories.bootstrapped_device!(%{tenant: ctx.tenant, intermediate: ctx.intermediate}, other_serial)

    {_priv, csr_pem} = issue_csr_pem()

    conn =
      run_enroll(ctx.bootstrap_certificate, %{
        "token" => other.plaintext_token,
        "csr_pem" => csr_pem
      })

    assert conn.status == 403
    assert Jason.decode!(conn.resp_body)["error"] == "token_device_mismatch"
  end

  test "missing fields → 400", ctx do
    conn = run_enroll(ctx.bootstrap_certificate, %{"token" => ctx.plaintext_token})
    assert conn.status == 400
  end
end
