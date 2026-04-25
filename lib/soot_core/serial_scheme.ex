defmodule SootCore.SerialScheme do
  @moduledoc """
  Defines how device serials are formatted and validated for a tenant.

  A serial has the shape

      <prefix>-<batch_padded>-<sequence_padded>[-<check_digit>]

  where `prefix` is a literal string (typically "<tenant>-<region>-<sku>"),
  the batch and sequence components are zero-padded to fixed widths, and
  an optional check digit is appended (`:luhn` for digit-only schemes, or
  `:none`).

  Generation and validation live as plain functions so they can be called
  during CSV import without going through Ash.

      iex> scheme = %SootCore.SerialScheme{prefix: "ACME-EU-WIDGET", batch_width: 4, sequence_width: 6, check_digit: :none}
      iex> SootCore.SerialScheme.generate!(scheme, 42, 1)
      "ACME-EU-WIDGET-0042-000001"
      iex> SootCore.SerialScheme.parse!(scheme, "ACME-EU-WIDGET-0042-000001")
      %{batch: 42, sequence: 1}
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

    attribute :name, :string do
      description "Operator-facing label, e.g. \"acme-eu-widget-v2\"."
      allow_nil? false
      public? true
    end

    attribute :prefix, :string do
      description "Literal string prepended to every serial."
      allow_nil? false
      public? true
    end

    attribute :batch_width, :integer, default: 4, public?: true
    attribute :sequence_width, :integer, default: 6, public?: true

    attribute :check_digit, :atom do
      constraints one_of: [:none, :luhn]
      default :none
      allow_nil? false
      public? true
    end

    attribute :metadata, :map, default: %{}, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name_per_tenant, [:tenant_id, :name],
      pre_check_with: SootCore.Domain
  end

  relationships do
    belongs_to :tenant, SootCore.Tenant do
      public? true
      attribute_writable? false
      destination_attribute :id
      source_attribute :tenant_id
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:tenant_id, :name, :prefix, :batch_width, :sequence_width, :check_digit, :metadata],
      update: [:name, :metadata]
    ]

    read :for_tenant do
      argument :tenant_id, :uuid, allow_nil?: false
      filter expr(tenant_id == ^arg(:tenant_id))
    end
  end

  code_interface do
    define :create, args: [:tenant_id, :name, :prefix]
    define :for_tenant, args: [:tenant_id]
  end

  # ─── Pure helpers (no Ash involvement) ────────────────────────────────

  @doc """
  Produce the serial for a `(batch, sequence)` pair under this scheme.
  Returns `{:ok, serial}` or `{:error, reason}`.
  """
  @spec generate(t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def generate(scheme, batch, sequence)
      when is_integer(batch) and batch >= 0 and is_integer(sequence) and sequence >= 0 do
    with :ok <- check_width(batch, scheme.batch_width, :batch_overflow),
         :ok <- check_width(sequence, scheme.sequence_width, :sequence_overflow) do
      base =
        [
          scheme.prefix,
          pad(batch, scheme.batch_width),
          pad(sequence, scheme.sequence_width)
        ]
        |> Enum.join("-")

      serial =
        case scheme.check_digit do
          :none -> base
          :luhn -> base <> "-" <> Integer.to_string(luhn_check(base))
        end

      {:ok, serial}
    end
  end

  @doc "Bang variant: raises on overflow."
  @spec generate!(t(), non_neg_integer(), non_neg_integer()) :: String.t()
  def generate!(scheme, batch, sequence) do
    case generate(scheme, batch, sequence) do
      {:ok, serial} -> serial
      {:error, reason} -> raise ArgumentError, "could not generate serial: #{inspect(reason)}"
    end
  end

  @doc """
  Parse a serial against a scheme; returns the embedded `(batch, sequence)`.
  """
  @spec parse(t(), String.t()) ::
          {:ok, %{batch: non_neg_integer(), sequence: non_neg_integer()}} | {:error, term()}
  def parse(scheme, serial) when is_binary(serial) do
    cond do
      not String.starts_with?(serial, scheme.prefix <> "-") ->
        {:error, :prefix_mismatch}

      true ->
        parts = String.split(serial, "-")
        expected_len = String.split(scheme.prefix, "-") |> length()
        expected_total = expected_len + 2 + check_extra(scheme.check_digit)

        if length(parts) != expected_total do
          {:error, :wrong_part_count}
        else
          suffix_parts = Enum.drop(parts, expected_len)
          do_parse(scheme, suffix_parts, serial)
        end
    end
  end

  @doc "Bang variant: raises on parse error."
  @spec parse!(t(), String.t()) :: %{batch: non_neg_integer(), sequence: non_neg_integer()}
  def parse!(scheme, serial) do
    case parse(scheme, serial) do
      {:ok, parts} -> parts
      {:error, reason} -> raise ArgumentError, "could not parse #{inspect(serial)}: #{inspect(reason)}"
    end
  end

  @doc """
  Validate that a serial conforms to a scheme. Equivalent to a successful
  `parse/2` plus a check-digit verification.
  """
  @spec validate(t(), String.t()) :: :ok | {:error, term()}
  def validate(scheme, serial) do
    case parse(scheme, serial) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  defp do_parse(scheme, [batch_str, seq_str], _full) when scheme.check_digit == :none do
    with {batch, ""} <- Integer.parse(batch_str),
         {seq, ""} <- Integer.parse(seq_str) do
      {:ok, %{batch: batch, sequence: seq}}
    else
      _ -> {:error, :invalid_numeric_component}
    end
  end

  defp do_parse(scheme, [batch_str, seq_str, check_str], full)
       when scheme.check_digit == :luhn do
    with {batch, ""} <- Integer.parse(batch_str),
         {seq, ""} <- Integer.parse(seq_str),
         {check, ""} <- Integer.parse(check_str),
         base <- String.replace_suffix(full, "-" <> check_str, ""),
         expected <- luhn_check(base),
         true <- check == expected || {:error, :invalid_check_digit} do
      {:ok, %{batch: batch, sequence: seq}}
    else
      {:error, _} = err -> err
      _ -> {:error, :invalid_numeric_component}
    end
  end

  defp do_parse(_scheme, _parts, _full), do: {:error, :malformed}

  defp check_extra(:none), do: 0
  defp check_extra(:luhn), do: 1

  defp pad(n, width) do
    n |> Integer.to_string() |> String.pad_leading(width, "0")
  end

  defp check_width(value, width, error) do
    if value >= :math.pow(10, width) do
      {:error, error}
    else
      :ok
    end
  end

  # Standard Luhn over the digit characters in `s` (non-digits ignored).
  @doc false
  def luhn_check(s) when is_binary(s) do
    digits =
      for <<c <- s>>, c in ?0..?9, do: c - ?0

    sum =
      digits
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.reduce(0, fn {d, i}, acc ->
        # Position 0 (the position the check digit would occupy) is doubled
        if rem(i, 2) == 0 do
          doubled = d * 2
          acc + if(doubled > 9, do: doubled - 9, else: doubled)
        else
          acc + d
        end
      end)

    rem(10 - rem(sum, 10), 10)
  end
end
