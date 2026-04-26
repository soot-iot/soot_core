defmodule Mix.Tasks.SootCore.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs soot_core: registers domain and mounts /enroll behind :device_mtls"
  end

  def example do
    "mix igniter.install soot_core"
  end

  def long_doc do
    """
    #{short_doc()}

    `SootCore.Domain` ships its `Tenant`, `SerialScheme`,
    `ProductionBatch`, `Device`, `DeviceShadow`, and `EnrollmentToken`
    resources as concrete library modules. The installer registers
    that domain in the operator's `:ash_domains` config rather than
    generating empty stub copies.

    The installer also creates a `:device_mtls` Phoenix pipeline (the
    first Soot library to need it) and mounts
    `forward "/enroll", SootCore.Plug.Enroll` inside that pipeline's
    scope. Sibling installers (`soot_telemetry`, `soot_contracts`)
    add their own forwards into the same scope.

    Composed by `mix soot.install`; can also be run standalone on a
    fresh project.

    See `GENERATOR-SPEC.md` in the `soot` package for the full design.

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

      * `--example` — same shape as the rest of the Soot installers;
        currently a no-op for `soot_core`.
      * `--yes` — answer yes to dependency-fetching prompts.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.SootCore.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"
    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :soot,
        example: __MODULE__.Docs.example(),
        only: nil,
        composes: [],
        schema: [example: :boolean, yes: :boolean],
        defaults: [example: false, yes: false],
        aliases: [y: :yes, e: :example]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:soot_core)
      |> register_domain()
      |> mount_enroll_route()
      |> note_next_steps()
    end

    defp register_domain(igniter) do
      app = Igniter.Project.Application.app_name(igniter)

      Igniter.Project.Config.configure(
        igniter,
        "config.exs",
        app,
        [:ash_domains],
        [SootCore.Domain],
        updater: fn list ->
          Igniter.Code.List.prepend_new_to_list(list, SootCore.Domain)
        end
      )
    end

    # Adds a `:device_mtls` pipeline (if missing) and a `forward
    # "/enroll", SootCore.Plug.Enroll` inside that scope. Idempotent:
    # detects an existing forward to SootCore.Plug.Enroll and leaves
    # the router alone if found.
    defp mount_enroll_route(igniter) do
      {igniter, router} =
        Igniter.Libs.Phoenix.select_router(
          igniter,
          "Which Phoenix router should the /enroll endpoint be mounted in?"
        )

      cond do
        router == nil ->
          Igniter.add_warning(igniter, """
          No Phoenix router found. The /enroll device-facing endpoint
          was not mounted. After your router is set up, re-run
          `mix igniter.install soot_core`.
          """)

        true ->
          igniter
          |> ensure_device_mtls_pipeline(router)
          |> maybe_add_enroll_forward(router)
      end
    end

    defp ensure_device_mtls_pipeline(igniter, router) do
      case Igniter.Libs.Phoenix.has_pipeline(igniter, router, :device_mtls) do
        {igniter, true} ->
          igniter

        {igniter, false} ->
          Igniter.Libs.Phoenix.add_pipeline(
            igniter,
            :device_mtls,
            "plug AshPki.Plug.MTLS, require_known_certificate: true",
            router: router
          )
      end
    end

    defp maybe_add_enroll_forward(igniter, router) do
      if enroll_route_present?(igniter, router) do
        igniter
      else
        Igniter.Libs.Phoenix.append_to_scope(
          igniter,
          "/",
          ~s|forward "/enroll", SootCore.Plug.Enroll|,
          router: router,
          with_pipelines: [:device_mtls]
        )
      end
    end

    defp enroll_route_present?(igniter, router) do
      {_, _source, zipper} = Igniter.Project.Module.find_module!(igniter, router)

      case Igniter.Code.Common.move_to(zipper, fn z ->
             Igniter.Code.Function.function_call?(z, :forward, 2) and
               Igniter.Code.Function.argument_equals?(z, 1, SootCore.Plug.Enroll)
           end) do
        {:ok, _} -> true
        :error -> false
      end
    end

    defp note_next_steps(igniter) do
      Igniter.add_notice(igniter, """
      soot_core installed.

      `SootCore.Domain` is registered in `:ash_domains`. It ships the
      `Tenant`, `SerialScheme`, `ProductionBatch`, `Device`,
      `DeviceShadow`, and `EnrollmentToken` resources as concrete
      library modules — no stubs to flesh out.

      The device-facing enrollment endpoint `/enroll` is mounted
      behind a new `:device_mtls` Phoenix pipeline (mTLS via
      `AshPki.Plug.MTLS`). Sibling Soot installers add their own
      forwards into the same scope.

      Next steps:

        mix ash.codegen --name install_soot_core
        mix ash.setup
      """)
    end
  end
else
  defmodule Mix.Tasks.SootCore.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"
    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task `soot_core.install` requires igniter. Add
      `{:igniter, "~> 0.6"}` to your project deps and try again, or
      invoke via:

          mix igniter.install soot_core

      For more information, see https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
