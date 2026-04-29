defmodule SootCore.PoliciesTest do
  @moduledoc """
  Boundary tests for the default `policies` blocks shipped with the
  six soot_core resources: Tenant, Device, EnrollmentToken,
  ProductionBatch, SerialScheme, DeviceShadow.
  """

  use ExUnit.Case, async: false

  alias SootCore.Actors
  alias SootCore.Test.Factories

  setup do
    Factories.reset_ets!()
    %{tenant: tenant} = Factories.fresh_tenant!("policy")
    scheme = Factories.fresh_scheme!(tenant.id, name: "policy-scheme")
    batch = Factories.fresh_batch!(tenant.id, scheme.id)

    {:ok, device} =
      SootCore.Device.create_unprovisioned(tenant.id, "POLICY-DEV-1", authorize?: false)

    {:ok, %{tenant: tenant, scheme: scheme, batch: batch, device: device}}
  end

  describe "SootCore.Tenant" do
    test ":enroller can read", %{tenant: tenant} do
      assert {:ok, ^tenant} =
               Ash.get(SootCore.Tenant, tenant.id, actor: Actors.system(:enroller))
    end

    test "no actor is forbidden", %{tenant: tenant} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.get(SootCore.Tenant, tenant.id)
    end

    test ":mtls_resolver is forbidden on Tenant", %{tenant: tenant} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.get(SootCore.Tenant, tenant.id, actor: Actors.system(:mtls_resolver))
    end
  end

  describe "SootCore.Device" do
    test ":enroller can read", %{device: device} do
      assert {:ok, ^device} =
               Ash.get(SootCore.Device, device.id, actor: Actors.system(:enroller))
    end

    test ":batch_provisioner can read", %{device: device} do
      assert {:ok, ^device} =
               Ash.get(SootCore.Device, device.id, actor: Actors.system(:batch_provisioner))
    end

    test ":mtls_resolver can read (used by SootCore.Plug.MTLS.Resolver)", %{device: device} do
      assert {:ok, ^device} =
               Ash.get(SootCore.Device, device.id, actor: Actors.system(:mtls_resolver))
    end

    test ":registry_sync is forbidden on Device", %{device: device} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.get(SootCore.Device, device.id, actor: Actors.system(:registry_sync))
    end

    test "no actor is forbidden", %{device: device} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.get(SootCore.Device, device.id)
    end
  end

  describe "SootCore.ProductionBatch" do
    test ":batch_provisioner can read", %{batch: batch} do
      assert {:ok, ^batch} =
               Ash.get(SootCore.ProductionBatch, batch.id,
                 actor: Actors.system(:batch_provisioner)
               )
    end

    test ":enroller is forbidden on ProductionBatch", %{batch: batch} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.get(SootCore.ProductionBatch, batch.id, actor: Actors.system(:enroller))
    end

    test "no actor is forbidden", %{batch: batch} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.get(SootCore.ProductionBatch, batch.id)
    end
  end

  describe "SootCore.SerialScheme" do
    test ":batch_provisioner can read", %{scheme: scheme} do
      assert {:ok, ^scheme} =
               Ash.get(SootCore.SerialScheme, scheme.id, actor: Actors.system(:batch_provisioner))
    end

    test "no actor is forbidden", %{scheme: scheme} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.get(SootCore.SerialScheme, scheme.id)
    end
  end

  describe "SootCore.EnrollmentToken" do
    setup ctx do
      valid_until = DateTime.utc_now() |> DateTime.add(600, :second)

      {:ok, et} =
        SootCore.EnrollmentToken.mint(ctx.tenant.id, ctx.device.id, valid_until,
          authorize?: false
        )

      Map.put(ctx, :token, et)
    end

    test ":enroller can read", %{token: token} do
      assert {:ok, %{id: id}} =
               Ash.get(SootCore.EnrollmentToken, token.id, actor: Actors.system(:enroller))

      assert id == token.id
    end

    test ":batch_provisioner can read", %{token: token} do
      assert {:ok, %{id: id}} =
               Ash.get(SootCore.EnrollmentToken, token.id,
                 actor: Actors.system(:batch_provisioner)
               )

      assert id == token.id
    end

    test "no actor is forbidden", %{token: token} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.get(SootCore.EnrollmentToken, token.id)
    end
  end

  describe "SootCore.DeviceShadow" do
    setup ctx do
      {:ok, shadow} = SootCore.DeviceShadow.create(ctx.device.id, authorize?: false)
      Map.put(ctx, :shadow, shadow)
    end

    test ":device_shadow_writer can read", %{shadow: shadow} do
      assert {:ok, ^shadow} =
               Ash.get(SootCore.DeviceShadow, shadow.id,
                 actor: Actors.system(:device_shadow_writer)
               )
    end

    test ":enroller is forbidden on DeviceShadow", %{shadow: shadow} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.get(SootCore.DeviceShadow, shadow.id, actor: Actors.system(:enroller))
    end

    test "no actor is forbidden", %{shadow: shadow} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.get(SootCore.DeviceShadow, shadow.id)
    end
  end
end
