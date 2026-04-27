defmodule SootCore.Resource.Device.Preparations do
  @moduledoc false

  defmodule GetBySerial do
    @moduledoc false
    use Ash.Resource.Preparation
    require Ash.Query

    @impl true
    def prepare(query, _opts, _context) do
      tenant_id = Ash.Query.get_argument(query, :tenant_id)
      serial = Ash.Query.get_argument(query, :serial)
      Ash.Query.filter(query, tenant_id == ^tenant_id and serial == ^serial)
    end
  end

  defmodule ForTenant do
    @moduledoc false
    use Ash.Resource.Preparation
    require Ash.Query

    @impl true
    def prepare(query, _opts, _context) do
      tenant_id = Ash.Query.get_argument(query, :tenant_id)
      Ash.Query.filter(query, tenant_id == ^tenant_id)
    end
  end
end
