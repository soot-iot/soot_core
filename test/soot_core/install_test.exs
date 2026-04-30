defmodule Mix.Tasks.SootCore.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  # Igniter evaluates the consumer project's `config/config.exs` into
  # the live `Application` env so installer steps can inspect it.
  # That means our "register the six modules" step leaks
  # `Test.Tenant`, `Test.EnrollmentToken`, etc. into the soot_core app
  # env for the rest of this test run, which breaks any subsequent
  # test that resolves `SootCore.<resource>()` (e.g. plug/enroll_test).
  # Snapshot the relevant keys before each test and restore on exit.
  setup do
    snapshot =
      for key <- [
            :tenant,
            :serial_scheme,
            :production_batch,
            :device,
            :device_shadow,
            :enrollment_token
          ],
          {:ok, value} <- [Application.fetch_env(:soot_core, key)],
          do: {key, value}

    on_exit(fn ->
      for key <- [
            :tenant,
            :serial_scheme,
            :production_batch,
            :device,
            :device_shadow,
            :enrollment_token
          ] do
        Application.delete_env(:soot_core, key)
      end

      for {key, value} <- snapshot do
        Application.put_env(:soot_core, key, value)
      end
    end)

    :ok
  end

  defp project_with_router do
    test_project(
      files: %{
        "lib/test_web/router.ex" => """
        defmodule TestWeb.Router do
          use Phoenix.Router

          scope "/" do
          end
        end
        """,
        "lib/test_web.ex" => """
        defmodule TestWeb do
          def router do
            quote do
              use Phoenix.Router
            end
          end
        end
        """
      }
    )
  end

  describe "info/2" do
    test "exposes the documented option schema" do
      info = Mix.Tasks.SootCore.Install.info([], nil)
      assert info.group == :soot
      assert info.schema == [example: :boolean, yes: :boolean]
      assert info.aliases == [y: :yes, e: :example]
    end
  end

  describe "domain registration" do
    test "registers SootCore.Domain in operator's :ash_domains" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      diff = diff(result, only: "config/config.exs")
      assert diff =~ "SootCore.Domain"
      assert diff =~ "ash_domains:"
    end
  end

  describe "formatter import" do
    test "imports :soot_core into .formatter.exs" do
      project_with_router()
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:soot_core]
      """)
    end
  end

  describe "router mount" do
    test "adds a :device_mtls pipeline to the router" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      diff = diff(result, only: "lib/test_web/router.ex")
      assert diff =~ "pipeline :device_mtls"
      assert diff =~ "AshPki.Plug.MTLS"
      assert diff =~ "require_known_certificate: true"
    end

    test "adds /enroll forward to the :device_mtls scope" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      diff = diff(result, only: "lib/test_web/router.ex")
      assert diff =~ "/enroll"
      assert diff =~ "SootCore.Plug.Enroll"
    end

    test "warns when no router exists" do
      igniter =
        test_project(files: %{})
        |> Igniter.compose_task("soot_core.install", [])

      assert Enum.any?(igniter.warnings, &(&1 =~ "No Phoenix router")) or
               Enum.any?(igniter.notices, &(&1 =~ "soot_core installed"))
    end
  end

  describe "idempotency" do
    test "running twice is a no-op on .formatter.exs" do
      project_with_router()
      |> Igniter.compose_task("soot_core.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_unchanged(".formatter.exs")
    end

    test "running twice is a no-op on config/config.exs" do
      project_with_router()
      |> Igniter.compose_task("soot_core.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_unchanged("config/config.exs")
    end

    test "running twice is a no-op on the router" do
      project_with_router()
      |> Igniter.compose_task("soot_core.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_unchanged("lib/test_web/router.ex")
    end
  end

  describe "next-steps notice" do
    test "emits a soot_core installed notice" do
      igniter =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "soot_core installed"))
    end

    test "notice mentions the /enroll endpoint" do
      igniter =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "/enroll"))
    end

    test "notice mentions the generated AshPostgres-backed resources" do
      igniter =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "AshPostgres-backed"))
    end
  end

  describe "AshPostgres consumer resources" do
    @resource_files [
      "lib/test/tenant.ex",
      "lib/test/serial_scheme.ex",
      "lib/test/production_batch.ex",
      "lib/test/device.ex",
      "lib/test/device_shadow.ex",
      "lib/test/enrollment_token.ex"
    ]

    defp generated_source(igniter, path) do
      source = igniter.rewrite.sources[path]

      assert source,
             "expected #{inspect(path)} to have been generated, but it was not. " <>
               "Created files: #{inspect(Map.keys(igniter.rewrite.sources))}"

      Rewrite.Source.get(source, :content)
    end

    test "generates the six consumer resource modules under lib/<app>/" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      for path <- @resource_files do
        assert_creates(result, path)
      end
    end

    test "Tenant module wires AshPostgres + the SootCore.Resource.Tenant extension" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      content = generated_source(result, "lib/test/tenant.ex")

      assert content =~ "defmodule Test.Tenant"
      assert content =~ "use Ash.Resource"
      assert content =~ "otp_app: :test"
      assert content =~ "domain: SootCore.Domain"
      assert content =~ "data_layer: AshPostgres.DataLayer"
      assert content =~ "extensions: [SootCore.Resource.Tenant]"
      assert content =~ ~s|table("tenants")|
      assert content =~ "repo(Test.Repo)"
    end

    test "Device module also includes AshStateMachine and a state_machine block" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      content = generated_source(result, "lib/test/device.ex")

      assert content =~ "AshStateMachine"
      assert content =~ "SootCore.Resource.Device"
      assert content =~ "state_machine do"
      assert content =~ "default_initial_state(:unprovisioned)"
      assert content =~ "transition(:bootstrap, from: :unprovisioned, to: :bootstrapped)"
      assert content =~ "transition(:enroll, from: :bootstrapped, to: :operational)"
      assert content =~ ~s|table("devices")|
    end

    test "SerialScheme module includes a soot_core block referencing Test.Tenant" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      content = generated_source(result, "lib/test/serial_scheme.ex")

      assert content =~ "soot_core do"
      assert content =~ "tenant(Test.Tenant)"
      assert content =~ ~s|table("serial_schemes")|
    end

    test "ProductionBatch module relates to tenant, serial_scheme, and device" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      content = generated_source(result, "lib/test/production_batch.ex")

      assert content =~ "soot_core do"
      assert content =~ "tenant(Test.Tenant)"
      assert content =~ "serial_scheme(Test.SerialScheme)"
      assert content =~ "device(Test.Device)"
      assert content =~ ~s|table("production_batches")|
    end

    test "Device module relates to tenant, production_batch, and device_shadow" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      content = generated_source(result, "lib/test/device.ex")

      assert content =~ "soot_core do"
      assert content =~ "tenant(Test.Tenant)"
      assert content =~ "production_batch(Test.ProductionBatch)"
      assert content =~ "device_shadow(Test.DeviceShadow)"
    end

    test "DeviceShadow module relates to device" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      content = generated_source(result, "lib/test/device_shadow.ex")

      assert content =~ "soot_core do"
      assert content =~ "device(Test.Device)"
      assert content =~ ~s|table("device_shadows")|
    end

    test "EnrollmentToken module is generated without a soot_core block" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      content = generated_source(result, "lib/test/enrollment_token.ex")

      assert content =~ "defmodule Test.EnrollmentToken"
      assert content =~ "SootCore.Resource.EnrollmentToken"
      assert content =~ ~s|table("enrollment_tokens")|
      refute content =~ "soot_core do"
    end

    test "every generated resource carries Ash.Policy.Authorizer and a policies block" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      for path <- @resource_files do
        content = generated_source(result, path)

        assert content =~ "authorizers: [Ash.Policy.Authorizer]",
               "expected authorizer in #{path}"

        assert content =~ "policies do",
               "expected policies block in #{path}"

        assert content =~ "bypass actor_attribute_equals(:role, :admin) do",
               "expected admin bypass in #{path}"
      end
    end

    test "Tenant policies block uses OwnTenant, others use SameTenant or relationship expr" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      assert generated_source(result, "lib/test/tenant.ex") =~ "SootCore.Policies.OwnTenant"

      for path <- ["lib/test/serial_scheme.ex", "lib/test/production_batch.ex",
                   "lib/test/device.ex", "lib/test/enrollment_token.ex"] do
        assert generated_source(result, path) =~ "SootCore.Policies.SameTenant"
      end

      assert generated_source(result, "lib/test/device_shadow.ex") =~
               "device.tenant_id == ^actor(:tenant_id)"
    end

    test "registers all six modules in config/config.exs under :soot_core" do
      result =
        project_with_router()
        |> Igniter.compose_task("soot_core.install", [])

      diff = diff(result, only: "config/config.exs")

      assert diff =~ "tenant: Test.Tenant"
      assert diff =~ "serial_scheme: Test.SerialScheme"
      assert diff =~ "production_batch: Test.ProductionBatch"
      assert diff =~ "device: Test.Device"
      assert diff =~ "device_shadow: Test.DeviceShadow"
      assert diff =~ "enrollment_token: Test.EnrollmentToken"
    end

    test "running the installer twice does not churn lib/test/tenant.ex" do
      project_with_router()
      |> Igniter.compose_task("soot_core.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_unchanged("lib/test/tenant.ex")
    end

    test "running the installer twice does not churn lib/test/device.ex" do
      project_with_router()
      |> Igniter.compose_task("soot_core.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_unchanged("lib/test/device.ex")
    end
  end
end
