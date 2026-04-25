defmodule SootCore.DeviceShadow do
  @moduledoc """
  Server-side representation of a device's shadow state.

  Holds two maps — `desired` (what the backend wants the device to be) and
  `reported` (what the device last said it is). The wire format used over
  MQTT is defined in `ash_mqtt`'s shadow DSL; this resource is the
  durable backing store.

  Last-write-wins per top-level key in v1; AWS/Azure-style nested merge is
  deferred.
  """

  use Ash.Resource,
    otp_app: :soot_core,
    domain: SootCore.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? false
  end

  attributes do
    uuid_primary_key :id

    attribute :device_id, :uuid, allow_nil?: false, public?: true
    attribute :desired, :map, default: %{}, public?: true
    attribute :reported, :map, default: %{}, public?: true
    attribute :last_reported_at, :utc_datetime_usec, public?: true
    attribute :version, :integer, default: 0, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :one_per_device, [:device_id], pre_check_with: SootCore.Domain
  end

  relationships do
    belongs_to :device, SootCore.Device do
      attribute_writable? false
      source_attribute :device_id
      destination_attribute :id
      public? true
    end
  end

  actions do
    defaults [:read, :destroy, create: [:device_id, :desired, :reported]]

    update :update_desired do
      accept [:desired]
      require_atomic? false
      change atomic_update(:version, expr(version + 1))
    end

    update :update_reported do
      accept [:reported]
      require_atomic? false
      change set_attribute(:last_reported_at, &DateTime.utc_now/0)
      change atomic_update(:version, expr(version + 1))
    end

    read :for_device do
      argument :device_id, :uuid, allow_nil?: false
      get? true
      filter expr(device_id == ^arg(:device_id))
    end
  end

  code_interface do
    define :create, args: [:device_id]
    define :update_desired, args: [:desired]
    define :update_reported, args: [:reported]
    define :for_device, args: [:device_id]
  end
end
