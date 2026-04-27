defmodule SootCore.Resource.ProductionBatch do
  @moduledoc """
  `Ash.Resource` extension that injects the `SootCore` production-batch
  schema into a consumer-owned resource module.

  Usage and override semantics mirror `SootCore.Resource.Tenant`. Sibling
  resources default to the in-library concretes; override via the
  `soot_core` DSL section:

      soot_core do
        tenant MyApp.Tenant
        serial_scheme MyApp.SerialScheme
        device MyApp.Device
      end

  Then register via `config :soot_core, production_batch: MyApp.ProductionBatch`.

  CSV-import logic for bulk Device creation lives on
  `SootCore.ProductionBatch.import_csv/3`; that helper resolves the
  configured resource modules at call time, so it remains correct for
  consumer overrides.
  """

  @soot_core %Spark.Dsl.Section{
    name: :soot_core,
    describe: """
    Sibling-resource references for this ProductionBatch resource.
    """,
    schema: [
      tenant: [
        type: :atom,
        default: SootCore.Tenant,
        doc: "The `Tenant` resource module this ProductionBatch belongs to."
      ],
      serial_scheme: [
        type: :atom,
        default: SootCore.SerialScheme,
        doc: "The `SerialScheme` resource module this ProductionBatch references."
      ],
      device: [
        type: :atom,
        default: SootCore.Device,
        doc: "The `Device` resource module produced by this ProductionBatch."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@soot_core],
    transformers: [SootCore.Resource.ProductionBatch.Transformers.Inject]
end
