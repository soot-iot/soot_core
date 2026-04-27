defmodule SootCore.ProductionBatch do
  @moduledoc """
  Default `ProductionBatch` resource shipped with `soot_core`.

  A manufacturing batch.

  Bulk-creates `Device` rows in `:unprovisioned` state. The CSV import
  function takes a stream of `serial[,model][,metadata_json]` rows and
  validates each serial against the batch's `SerialScheme`.

  The schema is provided by the `SootCore.Resource.ProductionBatch`
  extension. This default uses `Ash.DataLayer.Ets`; production
  deployments override with their own resource module backed by
  `AshPostgres.DataLayer` and register it via
  `config :soot_core, production_batch: MyApp.ProductionBatch`.

  `import_csv/3` resolves `SootCore.production_batch/0`,
  `SootCore.serial_scheme/0`, and `SootCore.device/0` at call time, so
  it remains correct under consumer overrides.
  """

  use Ash.Resource,
    otp_app: :soot_core,
    domain: SootCore.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [SootCore.Resource.ProductionBatch]

  ets do
    private? false
  end

  # ─── CSV import (plain function; bulk-creates Devices) ─────────────────

  NimbleCSV.define(__MODULE__.CSV, separator: ",", escape: "\"")

  @doc """
  Bulk-create Devices in `:unprovisioned` state from a CSV blob.

  The CSV must have a header row. Recognised columns:

    * `serial`    — required; validated against the batch's SerialScheme.
    * `model`     — optional; defaults to the batch's `model`.
    * `metadata`  — optional; JSON-encoded map.

  Returns `{:ok, %{inserted: count, errors: [...]}}`. Rows that fail
  validation are skipped; their error is included in `errors`.
  """
  @spec import_csv(String.t(), String.t(), keyword()) ::
          {:ok, %{inserted: non_neg_integer(), errors: [{integer(), term()}]}}
          | {:error, term()}
  def import_csv(batch_id, csv_blob, opts \\ []) when is_binary(csv_blob) do
    batch_module = SootCore.production_batch()
    scheme_module = SootCore.serial_scheme()
    device_module = SootCore.device()

    with {:ok, batch} <- Ash.get(batch_module, batch_id, authorize?: false),
         {:ok, scheme} <-
           Ash.get(scheme_module, batch.serial_scheme_id, authorize?: false) do
      [header | rows] =
        csv_blob
        |> __MODULE__.CSV.parse_string(skip_headers: false)

      header = Enum.map(header, &String.trim/1)

      result =
        rows
        |> Stream.with_index(2)
        |> Enum.reduce(%{inserted: 0, errors: []}, fn {row, line_no}, acc ->
          process_row(acc, header, row, line_no, batch, scheme, device_module, opts)
        end)

      {:ok, %{result | errors: Enum.reverse(result.errors)}}
    end
  end

  defp process_row(acc, header, row, line_no, batch, scheme, device_module, opts) do
    row_map = header |> Enum.zip(row) |> Map.new()

    with {:ok, serial} <- fetch_required(row_map, "serial"),
         :ok <- SootCore.SerialScheme.validate(scheme, serial),
         attrs <- build_attrs(batch, scheme, row_map, serial, opts),
         {:ok, _device} <-
           device_module.create_unprovisioned(
             batch.tenant_id,
             serial,
             attrs,
             authorize?: false
           ) do
      %{acc | inserted: acc.inserted + 1}
    else
      {:error, reason} -> %{acc | errors: [{line_no, reason} | acc.errors]}
    end
  end

  defp fetch_required(map, key) do
    case Map.get(map, key) do
      nil -> {:error, {:missing_column, key}}
      "" -> {:error, {:empty_column, key}}
      value -> {:ok, value}
    end
  end

  defp build_attrs(batch, scheme, row, _serial, opts) do
    metadata =
      case Map.get(row, "metadata") do
        nil -> %{}
        "" -> %{}
        json -> Jason.decode!(json)
      end

    %{
      batch_id: batch.id,
      serial_scheme_id: scheme.id,
      model: Map.get(row, "model") || batch.model || Keyword.get(opts, :default_model),
      metadata: metadata
    }
  end
end
