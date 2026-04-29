defmodule SootCore.Plug.MTLS.Resolver do
  @moduledoc """
  Resolves the verified mTLS certificate to the matching `Device` row
  and assigns it as the request actor.

  Mount immediately after `AshPki.Plug.MTLS` on any pipeline that
  serves device-initiated requests (telemetry ingest, shadow updates,
  command acknowledgements, etc.):

      pipeline :device_mtls do
        plug AshPki.Plug.MTLS
        plug SootCore.Plug.MTLS.Resolver
      end

  On success the resolver assigns:

    * `conn.assigns.actor` — the `Device` struct, ready to pass to
      Ash actions (`actor: conn.assigns.actor`). This is what
      resource policies pattern-match on.

    * `conn.assigns.soot_core_device` — alias of the same value, for
      callers that prefer an explicit name.

  The cert-derived `AshPki.Plug.MTLS.Actor` stays in
  `conn.assigns.ash_pki_actor` for endpoints that need the raw cert
  (e.g. enrollment, where the device's operational cert may not yet
  exist).

  ## Options

    * `:device` — the Device resource module to look up in.
      Defaults to whatever `SootCore.device/0` returns, which is the
      operator-overridable canonical Device.

    * `:require_device` — `:halt_with_403` (default), `:assign_only`,
      or `{:halt_with, fn conn, reason -> conn end}`. Halt on no
      matching row, or just leave `:actor` unset.

  ## Lookup

  The resolver matches the cert id against either
  `operational_certificate_id` (operational devices) or
  `bootstrap_certificate_id` (bootstrap devices that have not yet
  enrolled). It runs as `SootCore.Actors.system(:mtls_resolver)` so
  the lookup itself is policy-evaluable; no `authorize?: false`
  bypass.
  """

  @behaviour Plug
  import Plug.Conn
  require Ash.Query
  require Logger

  alias AshPki.Plug.MTLS.Actor

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    require_mode = Keyword.get(opts, :require_device, :halt_with_403)
    device_module = Keyword.get(opts, :device, SootCore.device())

    with {:ok, %Actor{certificate_id: cert_id}} <- fetch_actor(conn),
         true <- is_binary(cert_id) || {:error, :unknown_certificate},
         {:ok, device} <- load_device(device_module, cert_id) do
      conn
      |> assign(:actor, device)
      |> assign(:soot_core_device, device)
    else
      {:error, reason} -> handle_failure(conn, reason, require_mode)
    end
  end

  defp fetch_actor(%Plug.Conn{assigns: %{ash_pki_actor: %Actor{} = actor}}), do: {:ok, actor}
  defp fetch_actor(_), do: {:error, :missing_mtls_actor}

  defp load_device(device_module, cert_id) do
    device_module
    |> Ash.Query.filter(
      operational_certificate_id == ^cert_id or bootstrap_certificate_id == ^cert_id
    )
    |> Ash.read_one(actor: SootCore.Actors.system(:mtls_resolver))
    |> case do
      {:ok, nil} -> {:error, :no_matching_device}
      {:ok, device} -> {:ok, device}
      {:error, _} = err -> err
    end
  end

  defp handle_failure(conn, _reason, :assign_only), do: conn

  defp handle_failure(conn, reason, :halt_with_403) do
    body = Jason.encode!(%{error: "device_actor_unresolved", reason: inspect(reason)})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, body)
    |> halt()
  end

  defp handle_failure(conn, reason, {:halt_with, fun}) when is_function(fun, 2) do
    fun.(conn, reason)
  end
end
