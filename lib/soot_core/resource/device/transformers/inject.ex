defmodule SootCore.Resource.Device.Transformers.Inject do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias SootCore.Resource.Device.Preparations
  alias Spark.Dsl.Transformer

  @states [:unprovisioned, :bootstrapped, :operational, :quarantined, :retired]

  @impl true
  def before?(Ash.Resource.Transformers.BelongsToAttribute), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    domain = Transformer.get_persisted(dsl_state, :domain) || domain_from_dsl(dsl_state)

    tenant_module =
      Spark.Dsl.Extension.get_opt(dsl_state, [:soot_core], :tenant, SootCore.Tenant)

    batch_module =
      Spark.Dsl.Extension.get_opt(
        dsl_state,
        [:soot_core],
        :production_batch,
        SootCore.ProductionBatch
      )

    shadow_module =
      Spark.Dsl.Extension.get_opt(
        dsl_state,
        [:soot_core],
        :device_shadow,
        SootCore.DeviceShadow
      )

    with {:ok, dsl_state} <- add_attributes(dsl_state),
         {:ok, dsl_state} <- add_identities(dsl_state, domain),
         {:ok, dsl_state} <-
           add_relationships(dsl_state, tenant_module, batch_module, shadow_module),
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
           Builder.add_new_attribute(dsl_state, :batch_id, :uuid, public?: true),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :serial_scheme_id, :uuid, public?: true),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :serial, :string,
             description: "Tenant-unique device serial conforming to its SerialScheme.",
             allow_nil?: false,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :model, :string, public?: true),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :state, :atom,
             constraints: [one_of: @states],
             default: :unprovisioned,
             allow_nil?: false,
             public?: true
           ),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :bootstrap_certificate_id, :uuid, public?: true),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :operational_certificate_id, :uuid, public?: true),
         {:ok, dsl_state} <-
           Builder.add_new_attribute(dsl_state, :last_seen_at, :utc_datetime_usec, public?: true),
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
    Builder.add_new_identity(dsl_state, :unique_serial_per_tenant, [:tenant_id, :serial],
      pre_check_with: domain
    )
  end

  defp add_relationships(dsl_state, tenant_module, batch_module, shadow_module) do
    with {:ok, dsl_state} <-
           Builder.add_new_relationship(dsl_state, :belongs_to, :tenant, tenant_module,
             attribute_writable?: false,
             destination_attribute: :id,
             source_attribute: :tenant_id,
             public?: true,
             define_attribute?: false
           ),
         {:ok, dsl_state} <-
           Builder.add_new_relationship(dsl_state, :belongs_to, :batch, batch_module,
             attribute_writable?: false,
             destination_attribute: :id,
             source_attribute: :batch_id,
             public?: true,
             define_attribute?: false
           ) do
      Builder.add_new_relationship(dsl_state, :has_one, :shadow, shadow_module,
        destination_attribute: :device_id
      )
    end
  end

  defp add_actions(dsl_state) do
    with {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :read, :read, primary?: true),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :destroy, :destroy, primary?: true),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :create, :create_unprovisioned,
             description: "Insert a brand-new device in :unprovisioned state.",
             accept: [:tenant_id, :batch_id, :serial_scheme_id, :serial, :model, :metadata]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :bootstrap,
             description: "Attach a bootstrap certificate; transition to :bootstrapped.",
             accept: [:bootstrap_certificate_id],
             require_atomic?: false,
             changes: [
               Builder.build_action_change(
                 {AshStateMachine.BuiltinChanges.TransitionState, target: :bootstrapped}
               )
             ]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :enroll,
             description: "Attach an operational certificate; transition to :operational.",
             accept: [:operational_certificate_id],
             require_atomic?: false,
             changes: [
               Builder.build_action_change(
                 {AshStateMachine.BuiltinChanges.TransitionState, target: :operational}
               )
             ]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :quarantine,
             accept: [],
             require_atomic?: false,
             changes: [
               Builder.build_action_change(
                 {AshStateMachine.BuiltinChanges.TransitionState, target: :quarantined}
               )
             ]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :unquarantine,
             accept: [],
             require_atomic?: false,
             changes: [
               Builder.build_action_change(
                 {AshStateMachine.BuiltinChanges.TransitionState, target: :operational}
               )
             ]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :retire,
             accept: [],
             require_atomic?: false,
             changes: [
               Builder.build_action_change(
                 {AshStateMachine.BuiltinChanges.TransitionState, target: :retired}
               )
             ]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :update, :touch,
             description: "Stamp last_seen_at to now.",
             accept: [],
             require_atomic?: false,
             changes: [
               Builder.build_action_change(
                 {Ash.Resource.Change.SetAttribute,
                  attribute: :last_seen_at, value: &DateTime.utc_now/0}
               )
             ]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_action(dsl_state, :read, :get_by_serial,
             arguments: [
               Builder.build_action_argument(:tenant_id, :uuid, allow_nil?: false),
               Builder.build_action_argument(:serial, :string, allow_nil?: false)
             ],
             get?: true,
             preparations: [Builder.build_preparation(Preparations.GetBySerial)]
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
           Builder.add_new_interface(dsl_state, :create_unprovisioned,
             args: [:tenant_id, :serial]
           ),
         {:ok, dsl_state} <-
           Builder.add_new_interface(dsl_state, :bootstrap, args: [:bootstrap_certificate_id]),
         {:ok, dsl_state} <-
           Builder.add_new_interface(dsl_state, :enroll, args: [:operational_certificate_id]),
         {:ok, dsl_state} <- Builder.add_new_interface(dsl_state, :quarantine),
         {:ok, dsl_state} <- Builder.add_new_interface(dsl_state, :unquarantine),
         {:ok, dsl_state} <- Builder.add_new_interface(dsl_state, :retire),
         {:ok, dsl_state} <- Builder.add_new_interface(dsl_state, :touch),
         {:ok, dsl_state} <-
           Builder.add_new_interface(dsl_state, :get_by_serial, args: [:tenant_id, :serial]) do
      Builder.add_new_interface(dsl_state, :for_tenant, args: [:tenant_id])
    end
  end
end
