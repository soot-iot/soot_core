defmodule SootCore.Resource.Tenant do
  @moduledoc """
  `Ash.Resource` extension that injects the `SootCore` tenant schema
  (attributes, identities, actions, code interface) into a consumer-owned
  resource module.

  ## Usage

      defmodule MyApp.Tenant do
        use Ash.Resource,
          domain: MyApp.Domain,
          data_layer: AshPostgres.DataLayer,
          extensions: [SootCore.Resource.Tenant]

        postgres do
          table "tenants"
          repo MyApp.Repo
        end
      end

  Then register the module so the rest of `soot_core` resolves through it:

      config :soot_core, tenant: MyApp.Tenant

  Anything the consumer defines themselves (an attribute, an action, an
  identity) takes precedence — the extension uses `add_new_*` builders that
  no-op when the entity already exists.
  """

  use Spark.Dsl.Extension,
    transformers: [SootCore.Resource.Tenant.Transformers.Inject]
end
