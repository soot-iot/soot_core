defmodule SootCore.Resource.DeviceShadow.Preparations do
  @moduledoc false

  defmodule ForDevice do
    @moduledoc false
    use Ash.Resource.Preparation
    require Ash.Query

    @impl true
    def prepare(query, _opts, _context) do
      device_id = Ash.Query.get_argument(query, :device_id)
      Ash.Query.filter(query, device_id == ^device_id)
    end
  end
end
