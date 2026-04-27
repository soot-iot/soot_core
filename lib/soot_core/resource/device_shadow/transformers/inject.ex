defmodule SootCore.Resource.DeviceShadow.Transformers.Inject do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias SootCore.Resource.DeviceShadow.Preparations
  alias Spark.Dsl.Transformer

  require Ash.Expr

  @bump_version_change Builder.build_action_change(
                         {Ash.Resource.Change.Atomic,
                          attribute: :version,
                          expr: Ash.Expr.expr(version + 1),
                          cast_atomic?: true}
                       )

  @impl true
  def before?(Ash.Resource.Transformers.BelongsToAttribute), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    domain = Transformer.get_persisted(dsl_state, :domain) || domain_from_dsl(dsl_state)

    device_module =
      Spark.Dsl.Extension.get_opt(dsl_state, [:soot_core], :device, SootCore.Device)

    with {:ok, dsl_state} <- add_attributes(dsl_state),
         {:ok, dsl_state} <- add_identities(dsl_state, domain),
         {:ok, dsl_state} <- add_relationships(dsl_state, device_module),
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
           Builder.add_new_attribute(dsl_state, :device_id, :uuid,
             allow_nil?: false,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :desired, :map, default: %{}, public?: true),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :reported, :map, default: %{}, public?: true),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :last_reported_at, :utc_datetime_usec,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :version, :integer, default: 0, public?: true),
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
    Builder.add_new_identity(dsl_state, :one_per_device, [:device_id], pre_check_with: domain)
  end

  defp add_relationships(dsl_state, device_module) do
    Builder.add_new_relationship(dsl_state, :belongs_to, :device, device_module,
      attribute_writable?: false,
      source_attribute: :device_id,
      destination_attribute: :id,
      public?: true,
      define_attribute?: false
    )
  end

  defp add_actions(dsl_state) do
    with {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :read, :read, primary?: true),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :destroy, :destroy, primary?: true),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :create, :create,
             primary?: true,
             accept: [:device_id, :desired, :reported]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :update_desired,
             accept: [:desired],
             require_atomic?: false,
             changes: [@bump_version_change]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :update_reported,
             accept: [:reported],
             require_atomic?: false,
             changes: [
               Builder.build_action_change(
                 {Ash.Resource.Change.SetAttribute,
                  attribute: :last_reported_at, value: &DateTime.utc_now/0}
               ),
               @bump_version_change
             ]
           ) do
      Builder.add_new_action(dsl_state, :read, :for_device,
        arguments: [
          Builder.build_action_argument(:device_id, :uuid, allow_nil?: false)
        ],
        get?: true,
        preparations: [Builder.build_preparation(Preparations.ForDevice)]
      )
    end
  end

  defp add_code_interface(dsl_state) do
    with {:ok, dsl_state} <- Builder.add_new_interface(dsl_state, :create, args: [:device_id]),
         {:ok, dsl_state} <-
           Builder.add_new_interface(dsl_state, :update_desired, args: [:desired]),
         {:ok, dsl_state} <-
           Builder.add_new_interface(dsl_state, :update_reported, args: [:reported]) do
      Builder.add_new_interface(dsl_state, :for_device, args: [:device_id])
    end
  end
end
