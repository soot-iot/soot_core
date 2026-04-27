defmodule SootCore.Resource.Tenant.Preparations do
  @moduledoc false

  defmodule GetBySlug do
    @moduledoc false
    use Ash.Resource.Preparation
    require Ash.Query

    @impl true
    def prepare(query, _opts, _context) do
      slug = Ash.Query.get_argument(query, :slug)
      Ash.Query.filter(query, slug == ^slug)
    end
  end
end
