defmodule SootCore.EnrollmentToken do
  @moduledoc """
  Single-use bootstrap credential, scoped to a single device.

  The token plaintext is shown exactly once at mint time via
  `context.plaintext_token` on the create action. The DB stores only the
  SHA-256 hash. Replay protection: `consume!/1` verifies the token has
  not yet been used and stamps `used_at` atomically.

  This resource is the IoT-flavored counterpart of
  `AshPki.EnrollmentToken`; the two intentionally do not share code (the
  PKI bootstrap-cert workflow and the device-row enrollment workflow are
  different lifecycles).
  """

  use Ash.Resource,
    otp_app: :soot_core,
    domain: SootCore.Domain,
    data_layer: Ash.DataLayer.Ets

  require Ash.Query

  ets do
    private? false
  end

  attributes do
    uuid_primary_key :id

    attribute :tenant_id, :uuid, allow_nil?: false, public?: true
    attribute :device_id, :uuid, allow_nil?: false, public?: true

    attribute :token_hash, :string do
      allow_nil? false
      public? false
      sensitive? true
    end

    attribute :valid_until, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :used_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_hash, [:token_hash], pre_check_with: SootCore.Domain
  end

  actions do
    defaults [:read, :destroy]

    create :mint do
      description "Mint a fresh token. Plaintext is exposed once via context.plaintext_token."
      accept [:tenant_id, :device_id, :valid_until]

      change before_action(fn changeset, _ ->
               token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
               hash = hash_token(token)

               changeset
               |> Ash.Changeset.force_change_attribute(:token_hash, hash)
               |> Ash.Changeset.put_context(:plaintext_token, token)
             end)

      change after_action(fn changeset, record, _ctx ->
               plaintext = Map.get(changeset.context, :plaintext_token)
               {:ok, Ash.Resource.put_metadata(record, :plaintext_token, plaintext)}
             end)
    end

    update :consume do
      description "Mark the token used. Errors if already consumed."
      accept []
      require_atomic? false

      validate fn changeset, _ ->
        case Ash.Changeset.get_data(changeset, :used_at) do
          nil -> :ok
          _ -> {:error, field: :used_at, message: "token already used"}
        end
      end

      change set_attribute(:used_at, &DateTime.utc_now/0)
    end

    read :find_active do
      description "Look up a not-yet-used, not-yet-expired token by its plaintext."
      argument :token, :string, allow_nil?: false
      get? true

      prepare fn query, _ ->
        plaintext = Ash.Query.get_argument(query, :token)
        hash = hash_token(plaintext)
        now = DateTime.utc_now()

        Ash.Query.filter(
          query,
          token_hash == ^hash and is_nil(used_at) and valid_until > ^now
        )
      end
    end
  end

  code_interface do
    define :mint, args: [:tenant_id, :device_id, :valid_until]
    define :consume
    define :find_active, args: [:token]
  end

  @doc false
  def hash_token(token) when is_binary(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
