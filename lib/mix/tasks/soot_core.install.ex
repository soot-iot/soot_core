defmodule Mix.Tasks.SootCore.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs the Soot core devices domain into a project"
  end

  def example do
    "mix igniter.install soot_core"
  end

  def long_doc do
    """
    #{short_doc()}

    Generates a `Devices` domain in the operator's app, plus stub
    resources for `Tenant`, `SerialScheme`, `ProductionBatch`,
    `Device`, and `EnrollmentToken`. The `Device` resource is wired
    with `AshStateMachine` so the operator can fill in the
    `unprovisioned → bootstrapped → operational ⇄ quarantined → retired`
    transitions documented in `SPEC.md` §5.2.

    Composed by `mix soot.install`; can also be run standalone on a
    fresh project.

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

      * `--example` — same shape as the rest of the Soot installers;
        currently a no-op for `soot_core` since the resource stubs are
        already minimal starting points the operator extends.
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
      app_name = Igniter.Project.Application.app_name(igniter)
      devices_module = Igniter.Project.Module.module_name(igniter, "Devices")

      igniter
      |> Igniter.Project.Formatter.import_dep(:soot_core)
      |> create_devices_domain(devices_module)
      |> create_tenant(devices_module)
      |> create_serial_scheme(devices_module)
      |> create_production_batch(devices_module)
      |> create_device(devices_module)
      |> create_enrollment_token(devices_module)
      |> note_next_steps(app_name)
    end

    defp create_devices_domain(igniter, devices_module) do
      Igniter.Project.Module.create_module(
        igniter,
        devices_module,
        """
        @moduledoc \"\"\"
        Devices domain — owns the Soot core resources that describe
        the fleet (tenants, serial schemes, batches, devices, and
        enrollment tokens).

        Generated stub. Operators add their own resources to the
        `resources` block as the project grows; the framework does
        not re-touch this file once generated.
        \"\"\"

        use Ash.Domain, otp_app: :#{Igniter.Project.Application.app_name(igniter)}

        resources do
          resource #{inspect(Module.concat([devices_module, "Tenant"]))}
          resource #{inspect(Module.concat([devices_module, "SerialScheme"]))}
          resource #{inspect(Module.concat([devices_module, "ProductionBatch"]))}
          resource #{inspect(Module.concat([devices_module, "Device"]))}
          resource #{inspect(Module.concat([devices_module, "EnrollmentToken"]))}
        end
        """
      )
    end

    defp create_tenant(igniter, devices_module) do
      module = Module.concat([devices_module, "Tenant"])

      Igniter.Project.Module.create_module(
        igniter,
        module,
        """
        @moduledoc \"\"\"
        Top-level isolation boundary. Every other Soot resource is
        scoped to a tenant.

        Generated stub — fill in attributes, actions, and policies
        for your deployment.
        \"\"\"

        use Ash.Resource,
          otp_app: :#{Igniter.Project.Application.app_name(igniter)},
          domain: #{inspect(devices_module)}

        actions do
        end
        """
      )
    end

    defp create_serial_scheme(igniter, devices_module) do
      module = Module.concat([devices_module, "SerialScheme"])

      Igniter.Project.Module.create_module(
        igniter,
        module,
        """
        @moduledoc \"\"\"
        Serial-number scheme used to allocate device serials within a
        tenant (e.g. `ACME-{seq:6}`).

        Generated stub — fill in attributes, actions, and policies
        for your deployment.
        \"\"\"

        use Ash.Resource,
          otp_app: :#{Igniter.Project.Application.app_name(igniter)},
          domain: #{inspect(devices_module)}

        actions do
        end
        """
      )
    end

    defp create_production_batch(igniter, devices_module) do
      module = Module.concat([devices_module, "ProductionBatch"])

      Igniter.Project.Module.create_module(
        igniter,
        module,
        """
        @moduledoc \"\"\"
        Group of devices manufactured together. Used for bulk
        pre-provisioning and lifecycle reporting.

        Generated stub — fill in attributes, actions, and policies
        for your deployment.
        \"\"\"

        use Ash.Resource,
          otp_app: :#{Igniter.Project.Application.app_name(igniter)},
          domain: #{inspect(devices_module)}

        actions do
        end
        """
      )
    end

    defp create_device(igniter, devices_module) do
      module = Module.concat([devices_module, "Device"])

      Igniter.Project.Module.create_module(
        igniter,
        module,
        """
        @moduledoc \"\"\"
        A unit in the fleet.

        State machine (see `SPEC.md` §5.2):

            unprovisioned → bootstrapped → operational ⇄ quarantined
                                                ↓
                                             retired

        Generated stub — fill in the `state_machine` block,
        attributes, actions, and policies for your deployment.
        \"\"\"

        use Ash.Resource,
          otp_app: :#{Igniter.Project.Application.app_name(igniter)},
          domain: #{inspect(devices_module)},
          extensions: [AshStateMachine]

        actions do
        end
        """
      )
    end

    defp create_enrollment_token(igniter, devices_module) do
      module = Module.concat([devices_module, "EnrollmentToken"])

      Igniter.Project.Module.create_module(
        igniter,
        module,
        """
        @moduledoc \"\"\"
        Single-use token issued by the operator and redeemed by a
        device at `/enroll` to upgrade from a bootstrap cert to an
        operational cert.

        Generated stub — fill in attributes, actions, and policies
        for your deployment.
        \"\"\"

        use Ash.Resource,
          otp_app: :#{Igniter.Project.Application.app_name(igniter)},
          domain: #{inspect(devices_module)}

        actions do
        end
        """
      )
    end

    defp note_next_steps(igniter, app_name) do
      Igniter.add_notice(igniter, """
      soot_core installed.

      The Devices domain and resource stubs were generated under
      `lib/#{app_name}/devices/`. Each stub is a minimal starting
      point — flesh out attributes, actions, relationships, and
      policies as your fleet model grows.

      The Device resource is pre-wired with `AshStateMachine`. Add
      a `state_machine do ... end` block describing the
      `unprovisioned → bootstrapped → operational ⇄ quarantined → retired`
      transitions documented in `SPEC.md` §5.2.

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
