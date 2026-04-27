defmodule SootCore do
  @moduledoc """
  Tenant, Device, ProductionBatch, SerialScheme, EnrollmentToken, and the
  device state machine. Provides the multi-tenant primitives every other
  Soot library builds on.

  See `SootCore.Domain` for the resources and `SootCore.Plug.Enroll` for
  the device enrollment endpoint.

  ## Resource overrides

  Each resource ships as an `Ash.Resource` extension under
  `SootCore.Resource.*` plus a thin `Ash.DataLayer.Ets` default under
  `SootCore.*`. Production deployments declare their own resource
  modules backed by `AshPostgres.DataLayer` and register them via
  application config:

      config :soot_core,
        tenant: MyApp.Tenant,
        device: MyApp.Device,
        device_shadow: MyApp.DeviceShadow,
        enrollment_token: MyApp.EnrollmentToken,
        serial_scheme: MyApp.SerialScheme,
        production_batch: MyApp.ProductionBatch

  Internal `soot_core` callers resolve the active module through the
  helpers below (`tenant/0`, `device/0`, …), so any code path that
  observes the configured override automatically picks it up.
  """

  @doc "Configured `Tenant` resource module; defaults to `SootCore.Tenant`."
  @spec tenant() :: module()
  def tenant, do: Application.get_env(:soot_core, :tenant, SootCore.Tenant)

  @doc "Configured `Device` resource module; defaults to `SootCore.Device`."
  @spec device() :: module()
  def device, do: Application.get_env(:soot_core, :device, SootCore.Device)

  @doc "Configured `DeviceShadow` resource module; defaults to `SootCore.DeviceShadow`."
  @spec device_shadow() :: module()
  def device_shadow,
    do: Application.get_env(:soot_core, :device_shadow, SootCore.DeviceShadow)

  @doc "Configured `EnrollmentToken` resource module; defaults to `SootCore.EnrollmentToken`."
  @spec enrollment_token() :: module()
  def enrollment_token,
    do: Application.get_env(:soot_core, :enrollment_token, SootCore.EnrollmentToken)

  @doc "Configured `SerialScheme` resource module; defaults to `SootCore.SerialScheme`."
  @spec serial_scheme() :: module()
  def serial_scheme,
    do: Application.get_env(:soot_core, :serial_scheme, SootCore.SerialScheme)

  @doc "Configured `ProductionBatch` resource module; defaults to `SootCore.ProductionBatch`."
  @spec production_batch() :: module()
  def production_batch,
    do: Application.get_env(:soot_core, :production_batch, SootCore.ProductionBatch)
end
