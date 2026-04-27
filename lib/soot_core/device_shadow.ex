defmodule SootCore.DeviceShadow do
  @moduledoc """
  Default `DeviceShadow` resource shipped with `soot_core`.

  Server-side representation of a device's shadow state.

  Holds two maps — `desired` (what the backend wants the device to be) and
  `reported` (what the device last said it is). The wire format used over
  MQTT is defined in `ash_mqtt`'s shadow DSL; this resource is the
  durable backing store.

  Last-write-wins per top-level key in v1; AWS/Azure-style nested merge is
  deferred.

  The schema is provided by the `SootCore.Resource.DeviceShadow` extension.
  This default uses `Ash.DataLayer.Ets`; production deployments override
  with their own resource module backed by `AshPostgres.DataLayer` and
  register it via `config :soot_core, device_shadow: MyApp.DeviceShadow`.
  """

  use Ash.Resource,
    otp_app: :soot_core,
    domain: SootCore.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [SootCore.Resource.DeviceShadow]

  ets do
    private? false
  end
end
