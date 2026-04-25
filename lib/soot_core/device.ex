defmodule SootCore.Device do
  @moduledoc """
  A unit in the fleet.

  States (driven by `AshStateMachine`):

      unprovisioned → bootstrapped → operational ⇄ quarantined
                                          ↓
                                       retired

  - `unprovisioned`: row exists, no cert.
  - `bootstrapped`: bootstrap cert issued; the device may only call `/enroll`.
  - `operational`: operational cert in hand; full telemetry/command rights.
  - `quarantined`: a fast kill switch (policies refuse the device); cert
    not yet revoked.
  - `retired`: end-of-life; cert revoked, row retained for audit.
  """

  use Ash.Resource,
    otp_app: :soot_core,
    domain: SootCore.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  ets do
    private? false
  end

  state_machine do
    initial_states [:unprovisioned]
    default_initial_state :unprovisioned

    transitions do
      transition :bootstrap, from: :unprovisioned, to: :bootstrapped
      transition :enroll, from: :bootstrapped, to: :operational
      transition :quarantine, from: [:operational, :bootstrapped], to: :quarantined
      transition :unquarantine, from: :quarantined, to: :operational
      transition :retire, from: [:operational, :quarantined, :bootstrapped], to: :retired
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :tenant_id, :uuid, allow_nil?: false, public?: true
    attribute :batch_id, :uuid, public?: true
    attribute :serial_scheme_id, :uuid, public?: true

    attribute :serial, :string do
      description "Tenant-unique device serial conforming to its SerialScheme."
      allow_nil? false
      public? true
    end

    attribute :model, :string, public?: true

    attribute :state, :atom do
      constraints one_of: [:unprovisioned, :bootstrapped, :operational, :quarantined, :retired]
      default :unprovisioned
      allow_nil? false
      public? true
    end

    attribute :bootstrap_certificate_id, :uuid, public?: true
    attribute :operational_certificate_id, :uuid, public?: true

    attribute :last_seen_at, :utc_datetime_usec, public?: true
    attribute :metadata, :map, default: %{}, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_serial_per_tenant, [:tenant_id, :serial],
      pre_check_with: SootCore.Domain
  end

  relationships do
    belongs_to :tenant, SootCore.Tenant do
      attribute_writable? false
      destination_attribute :id
      source_attribute :tenant_id
      public? true
    end

    belongs_to :batch, SootCore.ProductionBatch do
      attribute_writable? false
      destination_attribute :id
      source_attribute :batch_id
      public? true
    end

    has_one :shadow, SootCore.DeviceShadow do
      destination_attribute :device_id
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create_unprovisioned do
      description "Insert a brand-new device in :unprovisioned state."
      accept [:tenant_id, :batch_id, :serial_scheme_id, :serial, :model, :metadata]
    end

    update :bootstrap do
      description "Attach a bootstrap certificate; transition to :bootstrapped."
      accept [:bootstrap_certificate_id]
      require_atomic? false
      change transition_state(:bootstrapped)
    end

    update :enroll do
      description "Attach an operational certificate; transition to :operational."
      accept [:operational_certificate_id]
      require_atomic? false
      change transition_state(:operational)
    end

    update :quarantine do
      accept []
      require_atomic? false
      change transition_state(:quarantined)
    end

    update :unquarantine do
      accept []
      require_atomic? false
      change transition_state(:operational)
    end

    update :retire do
      accept []
      require_atomic? false
      change transition_state(:retired)
    end

    update :touch do
      description "Stamp last_seen_at to now."
      accept []
      require_atomic? false
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
    end

    read :get_by_serial do
      argument :tenant_id, :uuid, allow_nil?: false
      argument :serial, :string, allow_nil?: false
      get? true
      filter expr(tenant_id == ^arg(:tenant_id) and serial == ^arg(:serial))
    end

    read :for_tenant do
      argument :tenant_id, :uuid, allow_nil?: false
      filter expr(tenant_id == ^arg(:tenant_id))
    end
  end

  code_interface do
    define :create_unprovisioned, args: [:tenant_id, :serial]
    define :bootstrap, args: [:bootstrap_certificate_id]
    define :enroll, args: [:operational_certificate_id]
    define :quarantine
    define :unquarantine
    define :retire
    define :touch
    define :get_by_serial, args: [:tenant_id, :serial]
    define :for_tenant, args: [:tenant_id]
  end
end
