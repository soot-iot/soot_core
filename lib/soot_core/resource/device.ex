defmodule SootCore.Resource.Device do
  @moduledoc """
  `Ash.Resource` extension that injects the `SootCore` device schema
  (attributes, identities, the relationships to tenant / production batch
  / shadow, the lifecycle actions, and the standard code interface) into
  a consumer-owned resource module.

  ## Usage

      defmodule MyApp.Device do
        use Ash.Resource,
          domain: MyApp.Domain,
          data_layer: AshPostgres.DataLayer,
          extensions: [AshStateMachine, SootCore.Resource.Device]

        postgres do
          table "devices"
          repo MyApp.Repo
        end

        state_machine do
          initial_states [:unprovisioned]
          default_initial_state :unprovisioned

          transitions do
            transition :bootstrap, from: :unprovisioned, to: :bootstrapped
            transition :enroll, from: :bootstrapped, to: :operational
            transition :quarantine, from: [:operational, :bootstrapped], to: :quarantined
            transition :unquarantine, from: :quarantined, to: :operational
            transition :retire,
              from: [:operational, :quarantined, :bootstrapped],
              to: :retired
          end
        end

        soot_core do
          tenant MyApp.Tenant
          production_batch MyApp.ProductionBatch
          device_shadow MyApp.DeviceShadow
        end
      end

  Then register the module so the rest of `soot_core` resolves through it:

      config :soot_core, device: MyApp.Device

  The consumer must list `AshStateMachine` and declare the `state_machine`
  block themselves — the lifecycle is part of the resource's contract and
  cannot be injected without compile-time knowledge of the consumer's
  extension list. The default `SootCore.Device` declares the canonical
  state machine; production overrides typically copy that block verbatim.

  Sibling resources default to the in-library concretes
  (`SootCore.Tenant` / `SootCore.ProductionBatch` /
  `SootCore.DeviceShadow`); override via the `soot_core` DSL section
  shown above when running with custom resources.
  """

  @soot_core %Spark.Dsl.Section{
    name: :soot_core,
    describe: """
    Sibling-resource references for this Device resource. Used at
    compile time to wire `belongs_to` / `has_one` relationships.
    """,
    schema: [
      tenant: [
        type: :atom,
        default: SootCore.Tenant,
        doc: "The `Tenant` resource module this Device belongs to."
      ],
      production_batch: [
        type: :atom,
        default: SootCore.ProductionBatch,
        doc: "The `ProductionBatch` resource module this Device belongs to."
      ],
      device_shadow: [
        type: :atom,
        default: SootCore.DeviceShadow,
        doc: "The `DeviceShadow` resource module that pairs with this Device."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@soot_core],
    transformers: [SootCore.Resource.Device.Transformers.Inject]
end
