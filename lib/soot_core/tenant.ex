defmodule SootCore.Tenant do
  @moduledoc """
  Default `Tenant` resource shipped with `soot_core`.

  Top-level isolation boundary. Every device, batch, and serial scheme is
  owned by a tenant. The tenant slug shows up in cert SANs
  (`URI:device://tenant-acme/devices/SN12345`), in MQTT topic prefixes,
  and in ClickHouse row policies.

  Multi-tenancy is mandatory from the start of `soot_core`; retrofitting it
  is painful, so the resource is required even for single-tenant
  deployments (which run with one tenant row).

  The schema is provided by the `SootCore.Resource.Tenant` extension. This
  default uses `Ash.DataLayer.Ets` so the library's own tests, demos, and
  smoke tasks run without a Postgres dependency. Production deployments
  declare their own resource module backed by `AshPostgres.DataLayer` and
  register it via `config :soot_core, tenant: MyApp.Tenant` — see
  `SootCore.Resource.Tenant` for the full pattern.
  """

  use Ash.Resource,
    otp_app: :soot_core,
    domain: SootCore.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [SootCore.Resource.Tenant]

  ets do
    private? false
  end
end
