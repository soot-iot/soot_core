defmodule SootCore.Resource.DeviceShadow do
  @moduledoc """
  `Ash.Resource` extension that injects the `SootCore` device-shadow
  schema (attributes, identity, relationship to the device, and the
  shadow-update actions) into a consumer-owned resource module.

  Usage and override semantics mirror `SootCore.Resource.Tenant`. Sibling
  resources default to the in-library concretes; override via the
  `soot_core` DSL section:

      soot_core do
        device MyApp.Device
      end

  Then register via `config :soot_core, device_shadow: MyApp.DeviceShadow`.
  """

  @soot_core %Spark.Dsl.Section{
    name: :soot_core,
    describe: """
    Sibling-resource references for this DeviceShadow resource.
    """,
    schema: [
      device: [
        type: :atom,
        default: SootCore.Device,
        doc: "The `Device` resource module that owns this shadow."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@soot_core],
    transformers: [SootCore.Resource.DeviceShadow.Transformers.Inject]
end
