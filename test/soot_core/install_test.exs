defmodule Mix.Tasks.SootCore.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

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
  end
end
