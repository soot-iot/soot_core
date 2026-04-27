defmodule SootCore.Test.Factories do
  @moduledoc false

  def reset_ets! do
    for resource <- [
          SootCore.Tenant,
          SootCore.SerialScheme,
          SootCore.ProductionBatch,
          SootCore.Device,
          SootCore.DeviceShadow,
          SootCore.EnrollmentToken,
          AshPki.Certificate,
          AshPki.CertificateAuthority,
          AshPki.RevocationList,
          AshPki.EnrollmentToken
        ] do
      try do
        :ets.delete_all_objects(resource)
      rescue
        _ -> :ok
      end
    end
  end

  def fresh_tenant!(slug \\ "acme") do
    {:ok, root} =
      AshPki.CertificateAuthority.create_root("root-#{slug}", "/CN=#{slug} root", %{
        validity_days: 365
      })

    {:ok, intermediate} =
      AshPki.CertificateAuthority.create_intermediate(
        "int-#{slug}",
        root.id,
        "/CN=#{slug} intermediate",
        %{validity_days: 180}
      )

    {:ok, tenant} =
      SootCore.Tenant.create(slug, "#{slug |> String.capitalize()} Inc", %{
        issuing_ca_id: intermediate.id
      })

    %{tenant: tenant, root: root, intermediate: intermediate}
  end

  def fresh_scheme!(tenant_id, opts \\ []) do
    name = Keyword.get(opts, :name, "scheme-#{System.unique_integer([:positive])}")
    prefix = Keyword.get(opts, :prefix, "ACME-EU-WIDGET")

    {:ok, scheme} =
      SootCore.SerialScheme.create(tenant_id, name, prefix, %{
        check_digit: Keyword.get(opts, :check_digit, :none)
      })

    scheme
  end

  def fresh_batch!(tenant_id, scheme_id, opts \\ []) do
    code = Keyword.get(opts, :code, "B-#{System.unique_integer([:positive])}")
    {:ok, batch} = SootCore.ProductionBatch.create(tenant_id, scheme_id, code)
    batch
  end

  @doc """
  Issue a bootstrap cert from the tenant's intermediate, persist the
  AshPki.Certificate row, and bootstrap a fresh device against it.
  Returns `{device, bootstrap_private_key, plaintext_token}`.
  """
  def bootstrapped_device!(ctx, serial) do
    %{tenant: tenant, intermediate: intermediate} = ctx

    bootstrap_priv = X509.PrivateKey.new_ec(:secp256r1)
    csr = X509.CSR.new(bootstrap_priv, "/CN=#{serial}")
    csr_pem = X509.CSR.to_pem(csr)

    {:ok, bootstrap_cert} =
      AshPki.Certificate.issue(intermediate.id, csr_pem, %{
        template: :client,
        validity_days: 1
      })

    {:ok, device} = SootCore.Device.create_unprovisioned(tenant.id, serial)
    {:ok, device} = SootCore.Device.bootstrap(device, bootstrap_cert.id)

    {:ok, et, plaintext} = mint_token(tenant.id, device.id)

    %{
      device: device,
      bootstrap_private_key: bootstrap_priv,
      bootstrap_certificate: bootstrap_cert,
      enrollment_token: et,
      plaintext_token: plaintext
    }
  end

  def mint_token(tenant_id, device_id, valid_for_seconds \\ 600) do
    valid_until = DateTime.utc_now() |> DateTime.add(valid_for_seconds, :second)

    {:ok, et} =
      SootCore.EnrollmentToken.mint(tenant_id, device_id, valid_until, authorize?: false)

    plaintext = et.__metadata__[:plaintext_token]
    {:ok, et, plaintext}
  end
end
