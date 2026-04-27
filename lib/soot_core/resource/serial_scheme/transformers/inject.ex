defmodule SootCore.Resource.SerialScheme.Transformers.Inject do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias SootCore.Resource.SerialScheme.Preparations
  alias Spark.Dsl.Transformer

  @check_digits [:none, :luhn]

  @impl true
  def before?(Ash.Resource.Transformers.BelongsToAttribute), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    domain = Transformer.get_persisted(dsl_state, :domain) || domain_from_dsl(dsl_state)

    tenant_module =
      Spark.Dsl.Extension.get_opt(dsl_state, [:soot_core], :tenant, SootCore.Tenant)

    with {:ok, dsl_state} <- add_attributes(dsl_state),
         {:ok, dsl_state} <- add_identities(dsl_state, domain),
         {:ok, dsl_state} <- add_relationships(dsl_state, tenant_module),
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
           Builder.add_new_attribute(dsl_state, :name, :string,
             description: "Operator-facing label, e.g. \"acme-eu-widget-v2\".",
             allow_nil?: false,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :prefix, :string,
             description: "Literal string prepended to every serial.",
             allow_nil?: false,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :batch_width, :integer,
             default: 4,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :sequence_width, :integer,
             default: 6,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :check_digit, :atom,
             constraints: [one_of: @check_digits],
             default: :none,
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
      :unique_name_per_tenant,
      [:tenant_id, :name],
      pre_check_with: domain
    )
  end

  defp add_relationships(dsl_state, tenant_module) do
    Builder.add_new_relationship(dsl_state, :belongs_to, :tenant, tenant_module,
      public?: true,
      attribute_writable?: false,
      destination_attribute: :id,
      source_attribute: :tenant_id,
      define_attribute?: false
    )
  end

  defp add_actions(dsl_state) do
    with {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :read, :read, primary?: true),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :destroy, :destroy, primary?: true, accept: []),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :create, :create,
             primary?: true,
             accept: [
               :tenant_id,
               :name,
               :prefix,
               :batch_width,
               :sequence_width,
               :check_digit,
               :metadata
             ]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :update,
             primary?: true,
             accept: [:name, :metadata]
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
           Builder.add_new_interface(dsl_state, :create, args: [:tenant_id, :name, :prefix]) do
      Builder.add_new_interface(dsl_state, :for_tenant, args: [:tenant_id])
    end
  end
end
