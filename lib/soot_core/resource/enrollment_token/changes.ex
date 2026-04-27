defmodule SootCore.Resource.EnrollmentToken.Changes do
  @moduledoc false

  defmodule MintToken do
    @moduledoc false
    use Ash.Resource.Change

    @impl true
    def change(changeset, _opts, _context) do
      changeset
      |> Ash.Changeset.before_action(&attach_hash/1)
      |> Ash.Changeset.after_action(&expose_plaintext/2)
    end

    defp attach_hash(changeset) do
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

      changeset
      |> Ash.Changeset.force_change_attribute(:token_hash, hash)
      |> Ash.Changeset.put_context(:plaintext_token, token)
    end

    defp expose_plaintext(changeset, record) do
      plaintext = Map.get(changeset.context, :plaintext_token)
      {:ok, Ash.Resource.put_metadata(record, :plaintext_token, plaintext)}
    end
  end

  defmodule ValidateUnused do
    @moduledoc false
    use Ash.Resource.Change

    @impl true
    def change(changeset, _opts, _context) do
      case Ash.Changeset.get_data(changeset, :used_at) do
        nil ->
          changeset

        _ ->
          Ash.Changeset.add_error(changeset, field: :used_at, message: "token already used")
      end
    end
  end
end
