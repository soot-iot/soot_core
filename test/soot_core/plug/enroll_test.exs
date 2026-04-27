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
    |> MTLS.call(
      MTLS.init(header_mode: {:enabled, "x-client-cert"}, require_known_certificate: true)
    )
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

    # chain_pem must contain *both* the leaf and the intermediate, in that order.
    chain = body["chain_pem"]
    cert_blocks = Regex.scan(~r/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/s, chain)
    assert length(cert_blocks) == 2

    {:ok, leaf_cert} = X509.Certificate.from_pem(body["certificate_pem"])
    {:ok, root_cert} = X509.Certificate.from_pem(ctx.root.certificate_pem)
    {:ok, inter_cert} = X509.Certificate.from_pem(ctx.intermediate.certificate_pem)

    der_chain = [
      X509.Certificate.to_der(inter_cert),
      X509.Certificate.to_der(leaf_cert)
    ]

    assert {:ok, _} =
             :public_key.pkix_path_validation(X509.Certificate.to_der(root_cert), der_chain, [])

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

    other =
      Factories.bootstrapped_device!(
        %{tenant: ctx.tenant, intermediate: ctx.intermediate},
        other_serial
      )

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
    assert Jason.decode!(conn.resp_body)["error"] == "missing_fields"
  end

  test "non-POST → 405", ctx do
    conn =
      conn(:get, "/enroll")
      |> put_req_header(
        "x-client-cert",
        URI.encode(ctx.bootstrap_certificate.certificate_pem, &URI.char_unreserved?/1)
      )
      |> MTLS.call(
        MTLS.init(header_mode: {:enabled, "x-client-cert"}, require_known_certificate: true)
      )
      |> SootCore.Plug.Enroll.call([])

    assert conn.status == 405
    assert Jason.decode!(conn.resp_body)["error"] == "method_not_allowed"
  end

  test "missing mTLS actor → 401" do
    conn =
      conn(:post, "/enroll", Jason.encode!(%{"token" => "x", "csr_pem" => "x"}))
      |> put_req_header("content-type", "application/json")
      |> SootCore.Plug.Enroll.call([])

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] == "mtls_required"
  end

  test "invalid JSON body → 400", ctx do
    pem = ctx.bootstrap_certificate.certificate_pem

    conn =
      conn(:post, "/enroll", "{not json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-client-cert", URI.encode(pem, &URI.char_unreserved?/1))
      |> MTLS.call(
        MTLS.init(header_mode: {:enabled, "x-client-cert"}, require_known_certificate: true)
      )
      |> SootCore.Plug.Enroll.call([])

    assert conn.status == 400
    assert Jason.decode!(conn.resp_body)["error"] == "invalid_body"
  end

  test "unknown / expired token → 403", ctx do
    {_priv, csr_pem} = issue_csr_pem()

    conn =
      run_enroll(ctx.bootstrap_certificate, %{
        "token" => "totally-bogus-token-string",
        "csr_pem" => csr_pem
      })

    assert conn.status == 403
    assert Jason.decode!(conn.resp_body)["error"] == "invalid_token"
  end

  test "tenant without an issuing CA → 500", ctx do
    # Mint a token + bootstrap a device under a tenant that has no
    # issuing_ca_id, but reuse the existing bootstrap cert (still on
    # file in AshPki) so MTLS passes and the enrollment plug reaches
    # the tenant resolution step.
    {:ok, broken_tenant} = SootCore.Tenant.create("broken", "Broken Tenant")
    {:ok, broken_device} = SootCore.Device.create_unprovisioned(broken_tenant.id, "BROKEN-1")
    {:ok, broken_device} = SootCore.Device.bootstrap(broken_device, ctx.bootstrap_certificate.id)
    {:ok, _et, plaintext} = Factories.mint_token(broken_tenant.id, broken_device.id)

    {_priv, csr_pem} = issue_csr_pem()

    conn =
      run_enroll(ctx.bootstrap_certificate, %{
        "token" => plaintext,
        "csr_pem" => csr_pem
      })

    assert conn.status == 500
    assert Jason.decode!(conn.resp_body)["error"] == "tenant_misconfigured"
  end

  test "suspended tenant → 403", ctx do
    {:ok, _} = SootCore.Tenant.suspend(ctx.tenant)

    {_priv, csr_pem} = issue_csr_pem()

    conn =
      run_enroll(ctx.bootstrap_certificate, %{
        "token" => ctx.plaintext_token,
        "csr_pem" => csr_pem
      })

    assert conn.status == 403
    assert Jason.decode!(conn.resp_body)["error"] == "tenant_inactive"
  end

  test "bootstrap cert chain-valid but not on file → 401", ctx do
    # Wipe every issued cert but keep the CAs, the device, and the token.
    # Now MTLS chain-validates (CAs still trusted), the actor is built
    # with certificate_id: nil (require_known_certificate: false), and the
    # plug rejects at the load_device step because no row links the cert
    # to a device.
    bootstrap_pem = ctx.bootstrap_certificate.certificate_pem
    :ets.delete_all_objects(AshPki.Certificate)

    {_priv, csr_pem} = issue_csr_pem()

    conn =
      conn(
        :post,
        "/enroll",
        Jason.encode!(%{"token" => ctx.plaintext_token, "csr_pem" => csr_pem})
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-client-cert", URI.encode(bootstrap_pem, &URI.char_unreserved?/1))
      |> MTLS.call(
        MTLS.init(
          header_mode: {:enabled, "x-client-cert"},
          require_known_certificate: false
        )
      )
      |> SootCore.Plug.Enroll.call([])

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] == "unknown_cert"
  end
end
