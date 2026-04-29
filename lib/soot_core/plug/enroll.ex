defmodule SootCore.Plug.Enroll do
  @moduledoc """
  Device enrollment endpoint.

  Mount inside an `AshPki.Plug.MTLS`-protected scope:

      forward "/enroll",
        to: Plug.Builder.compile([
          {AshPki.Plug.MTLS, [require_known_certificate: true]},
          SootCore.Plug.Enroll
        ])

  The device authenticates with its bootstrap cert (mTLS), POSTs a JSON
  body of:

      {"token": "<enrollment token plaintext>", "csr_pem": "-----BEGIN CERT REQ-----..."}

  On success the response is a 200 JSON body:

      {
        "certificate_pem": "-----BEGIN CERTIFICATE-----...",
        "chain_pem":       "<leaf>\\n<intermediate>",
        "device_id":       "<uuid>",
        "state":           "operational"
      }

  The device row's bootstrap_certificate_id must match the cert presented at
  the TLS layer; that link binds the token to the calling device. The
  token is single-use; replay yields 409.
  """

  @behaviour Plug
  import Plug.Conn

  require Logger

  alias AshPki.Plug.MTLS.Actor

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    with {:ok, %Actor{} = actor} <- fetch_actor(conn),
         {:ok, body} <- read_json_body(conn),
         {:ok, token, csr_pem} <- parse_body(body),
         {:ok, et} <- find_token(token),
         {:ok, device} <- load_device(actor, et),
         {:ok, tenant} <- load_tenant(device),
         {:ok, leaf, chain} <- issue_operational_cert(tenant, csr_pem),
         {:ok, device} <- transition_device(device, leaf),
         {:ok, _} <- consume_token(et) do
      respond(conn, 200, %{
        certificate_pem: leaf.certificate_pem,
        chain_pem: chain,
        device_id: device.id,
        state: Atom.to_string(device.state)
      })
    else
      {:error, reason} -> error_response(conn, reason)
    end
  end

  def call(conn, _opts) do
    error_response(conn, :method_not_allowed)
  end

  defp fetch_actor(%Plug.Conn{assigns: %{ash_pki_actor: %Actor{} = actor}}), do: {:ok, actor}
  defp fetch_actor(_), do: {:error, :missing_mtls_actor}

  defp read_json_body(conn) do
    {:ok, raw, _conn} = Plug.Conn.read_body(conn, length: 64 * 1024)

    case Jason.decode(raw) do
      {:ok, body} when is_map(body) -> {:ok, body}
      _ -> {:error, :invalid_json_body}
    end
  end

  defp parse_body(%{"token" => token, "csr_pem" => csr})
       when is_binary(token) and is_binary(csr),
       do: {:ok, token, csr}

  defp parse_body(_), do: {:error, :missing_required_fields}

  defp find_token(token) do
    case SootCore.enrollment_token().find_active(token, actor: enroller()) do
      {:ok, et} -> {:ok, et}
      {:error, _} -> {:error, :invalid_or_expired_token}
    end
  end

  defp load_device(%Actor{certificate_id: nil}, _et),
    do: {:error, :bootstrap_cert_not_on_file}

  defp load_device(%Actor{certificate_id: cert_id}, et) do
    require Ash.Query

    SootCore.device()
    |> Ash.Query.filter(bootstrap_certificate_id == ^cert_id and id == ^et.device_id)
    |> Ash.read_one(actor: enroller())
    |> case do
      {:ok, nil} -> {:error, :token_device_mismatch}
      {:ok, device} -> {:ok, device}
      {:error, _} -> {:error, :device_lookup_failed}
    end
  end

  defp load_tenant(device) do
    case Ash.get(SootCore.tenant(), device.tenant_id, actor: enroller()) do
      {:ok, %{status: :active, issuing_ca_id: ca_id} = tenant}
      when not is_nil(ca_id) ->
        {:ok, tenant}

      {:ok, %{status: status}} when status != :active ->
        {:error, {:tenant_not_active, status}}

      {:ok, %{issuing_ca_id: nil}} ->
        {:error, :tenant_has_no_issuing_ca}

      {:error, _} ->
        {:error, :tenant_lookup_failed}
    end
  end

  defp issue_operational_cert(tenant, csr_pem) do
    case AshPki.Certificate.issue(tenant.issuing_ca_id, csr_pem, %{
           template: :client,
           validity_days: 90
         }) do
      {:ok, leaf} ->
        chain_pem = build_chain_pem(leaf, tenant.issuing_ca_id)
        {:ok, leaf, chain_pem}

      {:error, reason} ->
        {:error, {:cert_issuance_failed, reason}}
    end
  end

  defp build_chain_pem(leaf, ca_id) do
    case Ash.get(AshPki.CertificateAuthority, ca_id, actor: enroller()) do
      {:ok, ca} -> leaf.certificate_pem <> ca.certificate_pem
      _ -> leaf.certificate_pem
    end
  end

  defp transition_device(device, leaf) do
    case SootCore.device().enroll(device, leaf.id, actor: enroller()) do
      {:ok, updated} -> {:ok, updated}
      {:error, reason} -> {:error, {:device_transition_failed, reason}}
    end
  end

  defp consume_token(et) do
    case SootCore.enrollment_token().consume(et, actor: enroller()) do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, {:token_consume_failed, reason}}
    end
  end

  defp enroller, do: SootCore.Actors.system(:enroller)

  defp respond(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  defp error_response(conn, reason) do
    {status, code} = status_for(reason)
    Logger.info("enroll rejected: #{inspect(reason)}")

    respond(conn, status, %{
      error: code,
      reason: inspect(reason)
    })
  end

  defp status_for(:method_not_allowed), do: {405, "method_not_allowed"}
  defp status_for(:missing_mtls_actor), do: {401, "mtls_required"}
  defp status_for(:bootstrap_cert_not_on_file), do: {401, "unknown_cert"}
  defp status_for(:invalid_json_body), do: {400, "invalid_body"}
  defp status_for(:missing_required_fields), do: {400, "missing_fields"}
  defp status_for(:invalid_or_expired_token), do: {403, "invalid_token"}
  defp status_for(:token_device_mismatch), do: {403, "token_device_mismatch"}
  defp status_for(:tenant_has_no_issuing_ca), do: {500, "tenant_misconfigured"}
  defp status_for({:tenant_not_active, _}), do: {403, "tenant_inactive"}
  defp status_for({:cert_issuance_failed, _}), do: {500, "issuance_failed"}
  defp status_for({:device_transition_failed, _}), do: {409, "transition_failed"}
  defp status_for({:token_consume_failed, _}), do: {409, "token_already_used"}
  defp status_for(_), do: {500, "internal_error"}
end
