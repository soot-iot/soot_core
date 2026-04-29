defmodule Mix.Tasks.SootCore.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs soot_core: registers domain, generates AshPostgres-backed resources, mounts /enroll behind :device_mtls"
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
    generating empty stub copies of the library defaults.

    The library defaults run on `Ash.DataLayer.Ets` so the soot_core
    test suite can run with zero infra, but Postgres is mandatory in
    the soot stack. The installer therefore composes
    `ash_postgres.install` (wiring the consumer's Repo + the
    `:ash_postgres` dep) and generates six AshPostgres-backed
    consumer resource modules under `lib/<app>/`:

      * `<App>.Tenant`            — table `tenants`
      * `<App>.SerialScheme`      — table `serial_schemes`
      * `<App>.ProductionBatch`   — table `production_batches`
      * `<App>.Device`            — table `devices` (`AshStateMachine`)
      * `<App>.DeviceShadow`      — table `device_shadows`
      * `<App>.EnrollmentToken`   — table `enrollment_tokens`

    Each generated module applies the matching
    `SootCore.Resource.<Name>` extension and (for the four resources
    with sibling references) declares the relationship targets via the
    `soot_core do … end` block. The six modules are then registered in
    `config/config.exs` under `:soot_core, <key>:` so the rest of
    soot_core picks them up at boot. Operators own the generated files
    post-install — edit `postgres do … end` blocks, add custom
    actions, etc. as needed.

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

    @resource_keys [
      :tenant,
      :serial_scheme,
      :production_batch,
      :device,
      :device_shadow,
      :enrollment_token
    ]

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :soot,
        example: __MODULE__.Docs.example(),
        only: nil,
        composes: ["ash_postgres.install"],
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
      |> compose_ash_postgres()
      |> generate_consumer_resources()
      |> register_consumer_resources()
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

    # `ash_postgres.install` handles the `:ash_postgres` dep, the Repo
    # module, the `:ecto_repos` config, and dev/test/runtime DB URLs.
    # Threading `--yes` through keeps the install non-interactive when
    # the parent installer is running with `-y`. The third-arg fallback
    # is a no-op so the installer's own test suite (which runs without
    # ash_postgres in deps) can still exercise the rest of the
    # pipeline; in real consumer projects `ash_postgres.install` is
    # available because the parent `mix igniter.install` resolves it.
    defp compose_ash_postgres(igniter) do
      argv = if igniter.args.options[:yes], do: ["--yes"], else: []
      Igniter.compose_task(igniter, "ash_postgres.install", argv, & &1)
    end

    defp generate_consumer_resources(igniter) do
      Enum.reduce(@resource_keys, igniter, fn key, acc ->
        generate_resource_module(acc, key)
      end)
    end

    defp generate_resource_module(igniter, key) do
      module = consumer_module_name(igniter, key)
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        repo = Igniter.Project.Module.module_name(igniter, "Repo")
        body = consumer_module_body(igniter, key, repo)
        Igniter.Project.Module.create_module(igniter, module, body)
      end
    end

    defp register_consumer_resources(igniter) do
      Enum.reduce(@resource_keys, igniter, fn key, acc ->
        module = consumer_module_name(acc, key)

        Igniter.Project.Config.configure(
          acc,
          "config.exs",
          :soot_core,
          [key],
          module
        )
      end)
    end

    defp consumer_module_name(igniter, key) do
      Igniter.Project.Module.module_name(igniter, camelize(key))
    end

    defp camelize(key), do: key |> Atom.to_string() |> Macro.camelize()

    defp consumer_module_body(igniter, :tenant, repo) do
      module = consumer_module_name(igniter, :tenant)

      """
      @moduledoc \"\"\"
      AshPostgres-backed `Tenant` resource generated by
      `mix soot_core.install`. Operators own this file — edit the
      `postgres do … end` block, add domain-specific actions, etc. as
      needed. The schema (attributes, identities, lifecycle actions)
      comes from the `SootCore.Resource.Tenant` extension and stays in
      sync with the rest of soot_core when this module is registered
      via `config :soot_core, tenant: #{inspect(module)}`.
      \"\"\"

      use Ash.Resource,
        otp_app: :#{otp_app(igniter)},
        domain: SootCore.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [SootCore.Resource.Tenant]

      postgres do
        table "tenants"
        repo #{inspect(repo)}
      end
      """
    end

    defp consumer_module_body(igniter, :serial_scheme, repo) do
      module = consumer_module_name(igniter, :serial_scheme)
      tenant = consumer_module_name(igniter, :tenant)

      """
      @moduledoc \"\"\"
      AshPostgres-backed `SerialScheme` resource generated by
      `mix soot_core.install`. Operators own this file. Schema comes
      from the `SootCore.Resource.SerialScheme` extension; sibling
      relationships are wired via the `soot_core do … end` block.
      Registered via `config :soot_core, serial_scheme: #{inspect(module)}`.
      \"\"\"

      use Ash.Resource,
        otp_app: :#{otp_app(igniter)},
        domain: SootCore.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [SootCore.Resource.SerialScheme]

      postgres do
        table "serial_schemes"
        repo #{inspect(repo)}
      end

      soot_core do
        tenant #{inspect(tenant)}
      end
      """
    end

    defp consumer_module_body(igniter, :production_batch, repo) do
      module = consumer_module_name(igniter, :production_batch)
      tenant = consumer_module_name(igniter, :tenant)
      serial_scheme = consumer_module_name(igniter, :serial_scheme)
      device = consumer_module_name(igniter, :device)

      """
      @moduledoc \"\"\"
      AshPostgres-backed `ProductionBatch` resource generated by
      `mix soot_core.install`. Operators own this file. Schema comes
      from the `SootCore.Resource.ProductionBatch` extension; sibling
      relationships are wired via the `soot_core do … end` block.
      Registered via `config :soot_core, production_batch: #{inspect(module)}`.
      \"\"\"

      use Ash.Resource,
        otp_app: :#{otp_app(igniter)},
        domain: SootCore.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [SootCore.Resource.ProductionBatch]

      postgres do
        table "production_batches"
        repo #{inspect(repo)}
      end

      soot_core do
        tenant #{inspect(tenant)}
        serial_scheme #{inspect(serial_scheme)}
        device #{inspect(device)}
      end
      """
    end

    defp consumer_module_body(igniter, :device, repo) do
      module = consumer_module_name(igniter, :device)
      tenant = consumer_module_name(igniter, :tenant)
      production_batch = consumer_module_name(igniter, :production_batch)
      device_shadow = consumer_module_name(igniter, :device_shadow)

      """
      @moduledoc \"\"\"
      AshPostgres-backed `Device` resource generated by
      `mix soot_core.install`. Operators own this file. Schema comes
      from the `SootCore.Resource.Device` extension; sibling
      relationships are wired via the `soot_core do … end` block. The
      `state_machine do … end` block mirrors `SootCore.Device`'s
      lifecycle (`unprovisioned → bootstrapped → operational ⇄
      quarantined → retired`). Registered via
      `config :soot_core, device: #{inspect(module)}`.
      \"\"\"

      use Ash.Resource,
        otp_app: :#{otp_app(igniter)},
        domain: SootCore.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [AshStateMachine, SootCore.Resource.Device]

      postgres do
        table "devices"
        repo #{inspect(repo)}
      end

      state_machine do
        initial_states([:unprovisioned])
        default_initial_state(:unprovisioned)

        transitions do
          transition(:bootstrap, from: :unprovisioned, to: :bootstrapped)
          transition(:enroll, from: :bootstrapped, to: :operational)
          transition(:quarantine, from: [:operational, :bootstrapped], to: :quarantined)
          transition(:unquarantine, from: :quarantined, to: :operational)
          transition(:retire, from: [:operational, :quarantined, :bootstrapped], to: :retired)
        end
      end

      soot_core do
        tenant #{inspect(tenant)}
        production_batch #{inspect(production_batch)}
        device_shadow #{inspect(device_shadow)}
      end
      """
    end

    defp consumer_module_body(igniter, :device_shadow, repo) do
      module = consumer_module_name(igniter, :device_shadow)
      device = consumer_module_name(igniter, :device)

      """
      @moduledoc \"\"\"
      AshPostgres-backed `DeviceShadow` resource generated by
      `mix soot_core.install`. Operators own this file. Schema comes
      from the `SootCore.Resource.DeviceShadow` extension; sibling
      relationships are wired via the `soot_core do … end` block.
      Registered via `config :soot_core, device_shadow: #{inspect(module)}`.
      \"\"\"

      use Ash.Resource,
        otp_app: :#{otp_app(igniter)},
        domain: SootCore.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [SootCore.Resource.DeviceShadow]

      postgres do
        table "device_shadows"
        repo #{inspect(repo)}
      end

      soot_core do
        device #{inspect(device)}
      end
      """
    end

    defp consumer_module_body(igniter, :enrollment_token, repo) do
      module = consumer_module_name(igniter, :enrollment_token)

      """
      @moduledoc \"\"\"
      AshPostgres-backed `EnrollmentToken` resource generated by
      `mix soot_core.install`. Operators own this file. Schema comes
      from the `SootCore.Resource.EnrollmentToken` extension.
      Registered via `config :soot_core, enrollment_token: #{inspect(module)}`.
      \"\"\"

      use Ash.Resource,
        otp_app: :#{otp_app(igniter)},
        domain: SootCore.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [SootCore.Resource.EnrollmentToken]

      postgres do
        table "enrollment_tokens"
        repo #{inspect(repo)}
      end
      """
    end

    defp otp_app(igniter), do: Igniter.Project.Application.app_name(igniter)

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

      if router == nil do
        Igniter.add_warning(igniter, """
        No Phoenix router found. The /enroll device-facing endpoint
        was not mounted. After your router is set up, re-run
        `mix igniter.install soot_core`.
        """)
      else
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

      `SootCore.Domain` is registered in `:ash_domains`. The six
      AshPostgres-backed consumer resources have been generated under
      `lib/<app>/` (Tenant, SerialScheme, ProductionBatch, Device,
      DeviceShadow, EnrollmentToken) and registered in
      `config/config.exs` under their respective `:soot_core, <key>:`
      keys. The Repo module and `:ash_postgres` dep were wired by the
      composed `ash_postgres.install`.

      Operators own the generated resource files — edit
      `postgres do … end` blocks, add custom actions, etc. as needed.

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
