defmodule SootCore.Resource.ProductionBatch.Transformers.Inject do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias SootCore.Resource.ProductionBatch.Preparations
  alias Spark.Dsl.Transformer

  @statuses [:open, :closed, :archived]

  @impl true
  def before?(Ash.Resource.Transformers.BelongsToAttribute), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    domain = Transformer.get_persisted(dsl_state, :domain) || domain_from_dsl(dsl_state)

    tenant_module =
      Spark.Dsl.Extension.get_opt(dsl_state, [:soot_core], :tenant, SootCore.Tenant)

    scheme_module =
      Spark.Dsl.Extension.get_opt(
        dsl_state,
        [:soot_core],
        :serial_scheme,
        SootCore.SerialScheme
      )

    device_module =
      Spark.Dsl.Extension.get_opt(dsl_state, [:soot_core], :device, SootCore.Device)

    with {:ok, dsl_state} <- add_attributes(dsl_state),
         {:ok, dsl_state} <- add_identities(dsl_state, domain),
         {:ok, dsl_state} <-
           add_relationships(dsl_state, tenant_module, scheme_module, device_module),
         {:ok, dsl_state} <- add_actions(dsl_state) do
      add_code_interface(dsl_state)
    end
  end

  defp domain_from_dsl(dsl_state) do
    Transformer.get_option(dsl_state, [:resource], :domain)
  end

  defp add_attributes(dsl_state) do
    with {:ok, dsl_state} <- ensure_uuid_primary_key(dsl_state),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :tenant_id, :uuid,
             allow_nil?: false,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :serial_scheme_id, :uuid,
             allow_nil?: false,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :code, :string,
             description: "Operator-facing batch identifier, e.g. \"2026-W17-A\".",
             allow_nil?: false,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :model, :string, public?: true),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :status, :atom,
             constraints: [one_of: @statuses],
             default: :open,
             allow_nil?: false,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :metadata, :map, default: %{}, public?: true),
         {:ok, dsl_state} <- Builder.add_new_create_timestamp(dsl_state, :inserted_at) do
      Builder.add_new_update_timestamp(dsl_state, :updated_at)
    end
  end

  defp ensure_uuid_primary_key(dsl_state) do
    if Ash.Resource.Info.attribute(dsl_state, :id) do
      {:ok, dsl_state}
    else
      Builder.add_new_attribute(dsl_state, :id, :uuid,
        primary_key?: true,
        allow_nil?: false,
        public?: true,
        default: &Ash.UUID.generate/0,
        match_other_defaults?: true
      )
    end
  end

  defp add_identities(dsl_state, domain) do
    Builder.add_new_identity(
      dsl_state,
      :unique_code_per_tenant,
      [:tenant_id, :code],
      pre_check_with: domain
    )
  end

  defp add_relationships(dsl_state, tenant_module, scheme_module, device_module) do
    with {:ok, dsl_state} <-
           Builder.add_new_relationship(dsl_state, :belongs_to, :tenant, tenant_module,
             attribute_writable?: false,
             source_attribute: :tenant_id,
             destination_attribute: :id,
             public?: true,
             define_attribute?: false
           ),
         {:ok, dsl_state} <-
           Builder.add_new_relationship(
             dsl_state,
             :belongs_to,
             :serial_scheme,
             scheme_module,
             attribute_writable?: false,
             source_attribute: :serial_scheme_id,
             destination_attribute: :id,
             public?: true,
             define_attribute?: false
           ) do
      Builder.add_new_relationship(dsl_state, :has_many, :devices, device_module,
        destination_attribute: :batch_id
      )
    end
  end

  defp add_actions(dsl_state) do
    with {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :read, :read, primary?: true),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :destroy, :destroy, primary?: true, accept: []),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :create, :create,
             primary?: true,
             accept: [:tenant_id, :serial_scheme_id, :code, :model, :metadata]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :update,
             primary?: true,
             accept: [:status, :metadata]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :close,
             accept: [],
             require_atomic?: false,
             changes: [
               Builder.build_action_change(
                 {Ash.Resource.Change.SetAttribute, attribute: :status, value: :closed}
               )
             ]
           ) do
      Builder.add_new_action(dsl_state, :read, :for_tenant,
        arguments: [
          Builder.build_action_argument(:tenant_id, :uuid, allow_nil?: false)
        ],
        preparations: [Builder.build_preparation(Preparations.ForTenant)]
      )
    end
  end

  defp add_code_interface(dsl_state) do
    with {:ok, dsl_state} <-
           Builder.add_new_interface(dsl_state, :create,
             args: [:tenant_id, :serial_scheme_id, :code]
           ),
         {:ok, dsl_state} <- Builder.add_new_interface(dsl_state, :close) do
      Builder.add_new_interface(dsl_state, :for_tenant, args: [:tenant_id])
    end
  end
end
