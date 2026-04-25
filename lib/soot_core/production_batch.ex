defmodule SootCore.ProductionBatch do
  @moduledoc """
  A manufacturing batch.

  Bulk-creates `Device` rows in `:unprovisioned` state. The CSV import
  action takes a stream of `serial[,model][,metadata_json]` rows and
  validates each serial against the batch's `SerialScheme`.
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

    attribute :tenant_id, :uuid, allow_nil?: false, public?: true
    attribute :serial_scheme_id, :uuid, allow_nil?: false, public?: true

    attribute :code, :string do
      description "Operator-facing batch identifier, e.g. \"2026-W17-A\"."
      allow_nil? false
      public? true
    end

    attribute :model, :string, public?: true

    attribute :status, :atom do
      constraints one_of: [:open, :closed, :archived]
      default :open
      allow_nil? false
      public? true
    end

    attribute :metadata, :map, default: %{}, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_code_per_tenant, [:tenant_id, :code], pre_check_with: SootCore.Domain
  end

  relationships do
    belongs_to :tenant, SootCore.Tenant do
      attribute_writable? false
      source_attribute :tenant_id
      destination_attribute :id
      public? true
    end

    belongs_to :serial_scheme, SootCore.SerialScheme do
      attribute_writable? false
      source_attribute :serial_scheme_id
      destination_attribute :id
      public? true
    end

    has_many :devices, SootCore.Device do
      destination_attribute :batch_id
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:tenant_id, :serial_scheme_id, :code, :model, :metadata],
      update: [:status, :metadata]
    ]

    update :close do
      accept []
      require_atomic? false
      change set_attribute(:status, :closed)
    end

    read :for_tenant do
      argument :tenant_id, :uuid, allow_nil?: false
      filter expr(tenant_id == ^arg(:tenant_id))
    end
  end

  code_interface do
    define :create, args: [:tenant_id, :serial_scheme_id, :code]
    define :close
    define :for_tenant, args: [:tenant_id]
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
    with {:ok, batch} <- Ash.get(__MODULE__, batch_id, authorize?: false),
         {:ok, scheme} <-
           Ash.get(SootCore.SerialScheme, batch.serial_scheme_id, authorize?: false) do
      [header | rows] =
        csv_blob
        |> __MODULE__.CSV.parse_string(skip_headers: false)

      header = Enum.map(header, &String.trim/1)

      result =
        rows
        |> Stream.with_index(2)
        |> Enum.reduce(%{inserted: 0, errors: []}, fn {row, line_no}, acc ->
          row_map = header |> Enum.zip(row) |> Map.new()

          with {:ok, serial} <- fetch_required(row_map, "serial"),
               :ok <- SootCore.SerialScheme.validate(scheme, serial),
               attrs <- build_attrs(batch, scheme, row_map, serial, opts),
               {:ok, _device} <-
                 SootCore.Device.create_unprovisioned(
                   batch.tenant_id,
                   serial,
                   attrs,
                   authorize?: false
                 ) do
            %{acc | inserted: acc.inserted + 1}
          else
            {:error, reason} ->
              %{acc | errors: [{line_no, reason} | acc.errors]}
          end
        end)

      {:ok, %{result | errors: Enum.reverse(result.errors)}}
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
