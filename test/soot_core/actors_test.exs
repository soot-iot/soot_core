defmodule SootCore.ActorsTest do
  use ExUnit.Case, async: true

  alias SootCore.Actors
  alias SootCore.Actors.System

  describe "system/1" do
    test "builds a System actor with the given part" do
      assert %System{part: :enroller, tenant_id: nil} = Actors.system(:enroller)
    end

    test "raises on a missing part (enforce_keys)" do
      assert_raise ArgumentError, fn ->
        struct!(System, [])
      end
    end
  end

  describe "system/2" do
    test "accepts a tenant_id binary" do
      assert %System{part: :enroller, tenant_id: "t-1"} =
               Actors.system(:enroller, "t-1")
    end

    test "accepts nil tenant" do
      assert %System{part: :enroller, tenant_id: nil} =
               Actors.system(:enroller, nil)
    end

    test "accepts a keyword list with :tenant_id" do
      assert %System{part: :registry_sync, tenant_id: "t-9"} =
               Actors.system(:registry_sync, tenant_id: "t-9")
    end

    test "keyword list without :tenant_id leaves it nil" do
      assert %System{part: :registry_sync, tenant_id: nil} =
               Actors.system(:registry_sync, [])
    end
  end

  describe "device/1 and user/1" do
    test "device/1 returns the struct unchanged" do
      d = %SootCore.Device{id: "d-1"}
      assert ^d = Actors.device(d)
    end

    defmodule UserFixture do
      defstruct [:id]
    end

    test "user/1 returns the struct unchanged" do
      u = %UserFixture{id: "u-1"}
      assert ^u = Actors.user(u)
    end
  end
end
