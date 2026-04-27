defmodule SootCore.Resource.EnrollmentToken.Preparations do
  @moduledoc false

  defmodule FindActive do
    @moduledoc false
    use Ash.Resource.Preparation
    require Ash.Query

    @impl true
    def prepare(query, _opts, _context) do
      plaintext = Ash.Query.get_argument(query, :token)
      hash = :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)
      now = DateTime.utc_now()

      Ash.Query.filter(
        query,
        token_hash == ^hash and is_nil(used_at) and valid_until > ^now
      )
    end
  end
end
