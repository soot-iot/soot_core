# `soot_core`

Tenants, devices, batches, enrollment tokens, the device state machine, and
the multi-tenancy primitive used throughout the Soot framework.

Depends on [`ash_pki`](../ash_pki). Brings in `ash_state_machine` for the
device lifecycle.

## Resources

* `SootCore.Tenant` — top-level isolation boundary. Owns an
  `issuing_ca_id` pointing at an `AshPki.CertificateAuthority`. Slug is
  unique and matches `~r/^[a-z][a-z0-9-]{1,62}$/`.
* `SootCore.SerialScheme` — describes how device serials are formatted.
  `prefix-batch-sequence[-luhn_check]`. Plain-function helpers
  (`generate/3`, `parse/2`, `validate/2`) so callers don't need Ash to
  validate a serial during CSV import.
* `SootCore.ProductionBatch` — manufacturing batch. `import_csv/3`
  bulk-creates `Device` rows in `:unprovisioned` state, skipping rows that
  fail serial validation and reporting them with line numbers.
* `SootCore.Device` — the unit. Drives the state machine:

      unprovisioned → bootstrapped → operational ⇄ quarantined
                                          ↓
                                       retired

* `SootCore.DeviceShadow` — durable backing for the device shadow
  (`desired` / `reported` maps; version counter; `last_reported_at`). The
  MQTT wire format is defined in `ash_mqtt`.
* `SootCore.EnrollmentToken` — single-use bootstrap credential. Plaintext
  is exposed once via `record.__metadata__[:plaintext_token]`; the DB only
  stores the SHA-256 hash. `consume/1` is replay-protected.

## Plug

* `SootCore.Plug.Enroll` — `POST /enroll`. Reads the bootstrap mTLS
  identity from `conn.assigns.ash_pki_actor` (set by `AshPki.Plug.MTLS`),
  consumes a `SootCore.EnrollmentToken`, signs the CSR via the tenant's
  issuing CA, transitions the device to `:operational`, and returns the
  operational cert chain. Token replay yields `409`; cross-device tokens
  yield `403`.

## Multi-tenancy

* Every resource carries `tenant_id`. Look-ups have `for_tenant`
  read actions.
* `SootCore.Policies.SameTenant` is a filter check that scopes a query to
  `actor.tenant_id`. Operators add it explicitly to resources they want
  enforced; `soot_core` doesn't bake it on by default so the embedded
  enrollment plug and other system-context code paths can act without an
  actor. To enforce per-tenant reads on a resource:

  ```elixir
  use Ash.Resource,
    ...,
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy action_type(:read) do
      authorize_if SootCore.Policies.SameTenant
    end
  end
  ```

## Demo

```elixir
{:ok, root} = AshPki.CertificateAuthority.create_root("root", "/CN=acme root")
{:ok, ca}   = AshPki.CertificateAuthority.create_intermediate("acme-int", root.id, "/CN=acme int")

{:ok, tenant} = SootCore.Tenant.create("acme", "Acme Inc", %{issuing_ca_id: ca.id})
{:ok, scheme} = SootCore.SerialScheme.create(tenant.id, "widget-v2", "ACME-EU-WIDGET")
{:ok, batch}  = SootCore.ProductionBatch.create(tenant.id, scheme.id, "2026-W17-A")

csv = """
serial,model
ACME-EU-WIDGET-0001-000001,widget-v2
ACME-EU-WIDGET-0001-000002,widget-v2
"""
{:ok, %{inserted: 2}} = SootCore.ProductionBatch.import_csv(batch.id, csv)
```

## Tests

```sh
mix test
```

24 tests across resource shapes, the state machine graph, CSV import,
plain-function serial helpers, the enrollment plug (happy path, replay
rejection, cross-device-token rejection, missing-field handling), and the
multi-tenancy filter primitive.

## Out of scope (v0.1)

* Device groups beyond tenant (the spec puts these in `soot_segments`).
* Device-to-device relationships and fleet-wide actions.
* Shadow conflict resolution beyond top-level last-write-wins.
