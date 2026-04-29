defmodule SootCore.Plug.MTLS.ResolverTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias AshPki.Plug.MTLS
  alias SootCore.Plug.MTLS.Resolver
  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    ctx = Factories.fresh_tenant!("acme")
    serial = "ACME-EU-WIDGET-0001-000001"
    bootstrap = Factories.bootstrapped_device!(ctx, serial)
    {:ok, Map.merge(ctx, bootstrap)}
  end

  defp run(conn_pem, opts \\ []) do
    conn(:get, "/")
    |> put_req_header("x-client-cert", URI.encode(conn_pem, &URI.char_unreserved?/1))
    |> MTLS.call(
      MTLS.init(header_mode: {:enabled, "x-client-cert"}, require_known_certificate: true)
    )
    |> Resolver.call(Resolver.init(opts))
  end

  test "resolves the bootstrap certificate to the matching device", ctx do
    conn = run(ctx.bootstrap_certificate.certificate_pem)

    refute conn.halted
    assert %SootCore.Device{} = conn.assigns.actor
    assert conn.assigns.actor.id == ctx.device.id
    assert conn.assigns.soot_core_device.id == ctx.device.id
  end

  test "resolves the operational certificate after enrollment", ctx do
    {:ok, op_cert} =
      AshPki.Certificate.issue(ctx.intermediate.id, op_csr_pem(), %{
        template: :client,
        validity_days: 90
      })

    {:ok, _} = SootCore.Device.enroll(ctx.device, op_cert.id, authorize?: false)
    conn = run(op_cert.certificate_pem)

    refute conn.halted
    assert conn.assigns.actor.id == ctx.device.id
  end

  test "halts with 403 when the cert matches no device", ctx do
    # Issue a fresh cert that no device row references.
    {:ok, stray} =
      AshPki.Certificate.issue(ctx.intermediate.id, op_csr_pem(), %{
        template: :client,
        validity_days: 90
      })

    conn = run(stray.certificate_pem)

    assert conn.halted
    assert conn.status == 403

    body = Jason.decode!(conn.resp_body)
    assert body["error"] == "device_actor_unresolved"
  end

  test ":assign_only mode leaves the conn unhalted with no :actor assign", ctx do
    {:ok, stray} =
      AshPki.Certificate.issue(ctx.intermediate.id, op_csr_pem(), %{
        template: :client,
        validity_days: 90
      })

    conn = run(stray.certificate_pem, require_device: :assign_only)

    refute conn.halted
    refute Map.has_key?(conn.assigns, :actor)
  end

  test "uses the configured device module when :device is supplied", ctx do
    conn = run(ctx.bootstrap_certificate.certificate_pem, device: SootCore.Device)
    refute conn.halted
    assert conn.assigns.actor.id == ctx.device.id
  end

  defp op_csr_pem do
    priv = X509.PrivateKey.new_ec(:secp256r1)
    csr = X509.CSR.new(priv, "/CN=op-cert-test")
    X509.CSR.to_pem(csr)
  end
end
