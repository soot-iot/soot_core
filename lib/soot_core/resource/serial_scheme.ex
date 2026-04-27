defmodule SootCore.Resource.SerialScheme do
  @moduledoc """
  `Ash.Resource` extension that injects the `SootCore` serial-scheme
  schema into a consumer-owned resource module.

  Usage and override semantics mirror `SootCore.Resource.Tenant`. Sibling
  resources default to the in-library concretes; override via the
  `soot_core` DSL section:

      soot_core do
        tenant MyApp.Tenant
      end

  Then register via `config :soot_core, serial_scheme: MyApp.SerialScheme`.

  Pure helpers for serial generation, parsing, and validation live on
  `SootCore.SerialScheme.Format` so they remain available regardless of
  which resource module the operator configures.
  """

  @soot_core %Spark.Dsl.Section{
    name: :soot_core,
    describe: """
    Sibling-resource references for this SerialScheme resource.
    """,
    schema: [
      tenant: [
        type: :atom,
        default: SootCore.Tenant,
        doc: "The `Tenant` resource module this SerialScheme belongs to."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@soot_core],
    transformers: [SootCore.Resource.SerialScheme.Transformers.Inject]
end
