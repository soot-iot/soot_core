defmodule SootCore.PolicyCaseTest do
  use SootCore.PolicyCase, async: true

  alias SootCore.Actors.System

  defmodule UserFixture do
    defstruct [:id]
  end

  describe "as_actor/2" do
    test "passes the actor to the function" do
      assert :hit = as_actor(:any_actor, fn :any_actor -> :hit end)
    end
  end

  describe "as_device/2" do
    test "passes a Device-like struct through" do
      d = %SootCore.Device{id: "d-1", tenant_id: "t-1"}
      assert ^d = as_device(d, fn actor -> actor end)
    end
  end

  describe "as_system/2" do
    test "builds a System actor with no tenant" do
      assert %System{part: :enroller, tenant_id: nil} =
               as_system(:enroller, fn actor -> actor end)
    end
  end

  describe "as_system/3" do
    test "builds a System actor with a tenant binary" do
      assert %System{part: :registry_sync, tenant_id: "t-7"} =
               as_system(:registry_sync, "t-7", fn actor -> actor end)
    end

    test "builds a System actor from keyword opts" do
      assert %System{part: :crl_publisher, tenant_id: "t-x"} =
               as_system(:crl_publisher, [tenant_id: "t-x"], fn actor -> actor end)
    end
  end

  describe "as_user/2" do
    test "passes a user-shaped struct through" do
      u = %UserFixture{id: "u-1"}
      assert ^u = as_user(u, fn actor -> actor end)
    end
  end

  describe "assert_forbidden/1" do
    test "passes when the function returns {:error, %Ash.Error.Forbidden{}}" do
      err = assert_forbidden(fn -> {:error, %Ash.Error.Forbidden{errors: []}} end)
      assert match?({:error, %Ash.Error.Forbidden{}}, err)
    end

    test "passes when the function raises Ash.Error.Forbidden" do
      err = assert_forbidden(fn -> raise Ash.Error.Forbidden end)
      assert %Ash.Error.Forbidden{} = err
    end

    test "passes when the function returns %Ash.Error.Forbidden{} bare" do
      err = assert_forbidden(fn -> %Ash.Error.Forbidden{errors: []} end)
      assert %Ash.Error.Forbidden{} = err
    end

    test "flunks when the function returns ok" do
      assert_raise ExUnit.AssertionError, ~r/expected Ash.Error.Forbidden/, fn ->
        assert_forbidden(fn -> {:ok, :nope} end)
      end
    end
  end
end
