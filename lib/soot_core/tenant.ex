defmodule SootCore.Tenant do
  @moduledoc """
  Top-level isolation boundary.

  Every device, batch, and serial scheme is owned by a tenant. The tenant
  slug shows up in cert SANs (`URI:device://tenant-acme/devices/SN12345`),
  in MQTT topic prefixes, and in ClickHouse row policies.

  Multi-tenancy is mandatory from the start of `soot_core`; retrofitting it
  is painful, so the resource is required even for single-tenant
  deployments (which run with one tenant row).
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

    attribute :slug, :string do
      description "URL-safe tenant identifier; appears in topics, SANs, ClickHouse row policies."
      allow_nil? false
      public? true
      constraints match: ~r/^[a-z][a-z0-9-]{1,62}$/
    end

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :status, :atom do
      constraints one_of: [:active, :suspended, :archived]
      default :active
      allow_nil? false
      public? true
    end

    attribute :issuing_ca_id, :uuid, public?: true,
      description: "AshPki.CertificateAuthority used to issue this tenant's device certs."

    attribute :metadata, :map, public?: true, default: %{}

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_slug, [:slug], pre_check_with: SootCore.Domain
  end

  actions do
    defaults [:read, :destroy, create: [:slug, :name, :issuing_ca_id, :metadata]]

    read :get_by_slug do
      argument :slug, :string, allow_nil?: false
      get? true
      filter expr(slug == ^arg(:slug))
    end

    update :suspend do
      accept []
      require_atomic? false
      change set_attribute(:status, :suspended)
    end

    update :reactivate do
      accept []
      require_atomic? false
      change set_attribute(:status, :active)
    end

    update :archive do
      accept []
      require_atomic? false
      change set_attribute(:status, :archived)
    end
  end

  code_interface do
    define :create, args: [:slug, :name]
    define :get_by_slug, args: [:slug]
    define :suspend
    define :reactivate
    define :archive
  end
end
