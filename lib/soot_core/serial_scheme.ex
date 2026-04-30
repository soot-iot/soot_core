defmodule SootCore.SerialScheme do
  @moduledoc """
  Default `SerialScheme` resource shipped with `soot_core`.

  Defines how device serials are formatted and validated for a tenant.

  A serial has the shape

      <prefix>-<batch_padded>-<sequence_padded>[-<check_digit>]

  where `prefix` is a literal string (typically "<tenant>-<region>-<sku>"),
  the batch and sequence components are zero-padded to fixed widths, and
  an optional check digit is appended (`:luhn` for digit-only schemes, or
  `:none`).

  Generation and validation live as plain functions on this module so
  they can be called during CSV import without going through Ash. The
  helpers operate on any struct whose fields match the `prefix`,
  `batch_width`, `sequence_width`, `check_digit` shape, so callers
  remain valid even when an operator overrides the resource module via
  `config :soot_core, serial_scheme: MyApp.SerialScheme`.

      iex> scheme = %SootCore.SerialScheme{prefix: "ACME-EU-WIDGET", batch_width: 4, sequence_width: 6, check_digit: :none}
      iex> SootCore.SerialScheme.generate!(scheme, 42, 1)
      "ACME-EU-WIDGET-0042-000001"
      iex> SootCore.SerialScheme.parse!(scheme, "ACME-EU-WIDGET-0042-000001")
      %{batch: 42, sequence: 1}

  The schema (attributes, identities, the tenant relationship, actions)
  is provided by the `SootCore.Resource.SerialScheme` extension.
  Production deployments override with their own resource module backed
  by `AshPostgres.DataLayer`.
  """

  use Ash.Resource,
    otp_app: :soot_core,
    domain: SootCore.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [SootCore.Resource.SerialScheme]

  ets do
    private? false
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
    if String.starts_with?(serial, scheme.prefix <> "-") do
      parts = String.split(serial, "-")
      expected_len = String.split(scheme.prefix, "-") |> length()
      expected_total = expected_len + 2 + check_extra(scheme.check_digit)

      if length(parts) != expected_total do
        {:error, :wrong_part_count}
      else
        suffix_parts = Enum.drop(parts, expected_len)
        do_parse(scheme, suffix_parts, serial)
      end
    else
      {:error, :prefix_mismatch}
    end
  end

  @doc "Bang variant: raises on parse error."
  @spec parse!(t(), String.t()) :: %{batch: non_neg_integer(), sequence: non_neg_integer()}
  def parse!(scheme, serial) do
    case parse(scheme, serial) do
      {:ok, parts} ->
        parts

      {:error, reason} ->
        raise ArgumentError, "could not parse #{inspect(serial)}: #{inspect(reason)}"
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
      |> Enum.reduce(0, fn {d, i}, acc -> acc + luhn_step(d, i) end)

    rem(10 - rem(sum, 10), 10)
  end

  # Position 0 (where the check digit would land) is doubled; if the doubled
  # value exceeds 9, subtract 9 (equivalent to summing its digits).
  defp luhn_step(d, i) when rem(i, 2) == 0 and d * 2 > 9, do: d * 2 - 9
  defp luhn_step(d, i) when rem(i, 2) == 0, do: d * 2
  defp luhn_step(d, _i), do: d
  # Default policies (POLICY-SPEC §4.1).
  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if SootCore.Policies.SameTenant
    end

    policy always() do
      access_type :strict
      authorize_if actor_attribute_equals(:part, :batch_provisioner)
      authorize_if actor_attribute_equals(:part, :seed)
    end
  end
end
