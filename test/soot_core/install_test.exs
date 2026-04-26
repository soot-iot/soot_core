defmodule Mix.Tasks.SootCore.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  describe "info/2" do
    test "exposes the documented option schema" do
      info = Mix.Tasks.SootCore.Install.info([], nil)
      assert info.group == :soot
      assert info.schema == [example: :boolean, yes: :boolean]
      assert info.aliases == [y: :yes, e: :example]
    end
  end

  describe "generated modules" do
    test "creates the Devices domain" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_creates("lib/test/devices.ex")
    end

    test "creates a Tenant resource stub" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_creates("lib/test/devices/tenant.ex")
    end

    test "creates a SerialScheme resource stub" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_creates("lib/test/devices/serial_scheme.ex")
    end

    test "creates a ProductionBatch resource stub" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_creates("lib/test/devices/production_batch.ex")
    end

    test "creates a Device resource stub with the AshStateMachine extension" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_core.install", [])

      assert_creates(result, "lib/test/devices/device.ex")

      device_diff = diff(result, only: "lib/test/devices/device.ex")
      assert device_diff =~ "AshStateMachine"
      assert device_diff =~ "unprovisioned"
      assert device_diff =~ "operational"
      assert device_diff =~ "retired"
    end

    test "creates an EnrollmentToken resource stub" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_creates("lib/test/devices/enrollment_token.ex")
    end
  end

  describe "formatter" do
    test "imports :soot_core in .formatter.exs" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:soot_core]
      """)
    end

    test "is idempotent on .formatter.exs" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_core.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_core.install", [])
      |> assert_unchanged(".formatter.exs")
    end
  end

  describe "next-steps notice" do
    test "emits a soot_core installed notice" do
      igniter =
        test_project(files: %{})
        |> Igniter.compose_task("soot_core.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "soot_core installed"))
    end
  end
end
