defmodule SootCore.PolicyCase do
  @moduledoc """
  Test helpers for exercising Ash policies with explicit actors.

  The canonical pattern: build an actor with `as_device/2`,
  `as_system/2`, or `as_user/2`, run the action under test, and
  assert on the result. The action under test always runs with a
  real actor — `authorize?: false` is allowed only in setup
  fixtures (see `SootCore.Test.Factories`).

      use SootCore.PolicyCase

      test "device updates own shadow" do
        device = factory(...)
        shadow = factory(...)

        assert {:ok, _} =
          as_device(device, fn actor ->
            SootCore.DeviceShadow.update_value(shadow, %{...}, actor: actor)
          end)
      end

      test "device cannot touch another's shadow" do
        ...
        assert_forbidden fn ->
          as_device(other, fn actor ->
            SootCore.DeviceShadow.update_value(shadow, %{...}, actor: actor)
          end)
        end
      end

  Helpers are exposed both as macros (via `use SootCore.PolicyCase`)
  and as plain functions on this module, so they work in any test
  setup.
  """

  defmacro __using__(opts) do
    async = Keyword.get(opts, :async, false)

    quote do
      use ExUnit.Case, async: unquote(async)
      import SootCore.PolicyCase
    end
  end

  alias SootCore.Actors

  @doc """
  Pass an actor to a function. Trivial wrapper; exists so tests read
  uniformly across actor kinds.
  """
  @spec as_actor(any(), (any() -> result)) :: result when result: var
  def as_actor(actor, fun) when is_function(fun, 1), do: fun.(actor)

  @doc """
  Run `fun` with a Device-as-actor.

  Accepts a `%SootCore.Device{}` (or operator override) struct.
  """
  @spec as_device(struct(), (struct() -> result)) :: result when result: var
  def as_device(%_{} = device, fun) when is_function(fun, 1) do
    fun.(Actors.device(device))
  end

  @doc """
  Run `fun` with a `System` actor for the given `part`.

  Optional second argument: a tenant id (binary), or `[tenant_id:
  ...]` keyword list.
  """
  @spec as_system(atom(), (Actors.System.t() -> result)) :: result when result: var
  def as_system(part, fun) when is_atom(part) and is_function(fun, 1) do
    fun.(Actors.system(part))
  end

  @spec as_system(atom(), keyword() | binary() | nil, (Actors.System.t() -> result)) :: result
        when result: var
  def as_system(part, scope, fun) when is_atom(part) and is_function(fun, 1) do
    fun.(Actors.system(part, scope))
  end

  @doc """
  Run `fun` with a User-as-actor.
  """
  @spec as_user(struct(), (struct() -> result)) :: result when result: var
  def as_user(%_{} = user, fun) when is_function(fun, 1) do
    fun.(Actors.user(user))
  end

  @doc """
  Assert that `fun` evaluates to a forbidden Ash result — either
  `{:error, %Ash.Error.Forbidden{}}`, a `Forbidden` struct directly,
  or a raised `Ash.Error.Forbidden` from a bang variant.
  """
  defmacro assert_forbidden(fun) do
    quote do
      try do
        case unquote(fun).() do
          {:error, %Ash.Error.Forbidden{}} = err ->
            err

          %Ash.Error.Forbidden{} = err ->
            err

          other ->
            ExUnit.Assertions.flunk("expected Ash.Error.Forbidden, got: #{inspect(other)}")
        end
      rescue
        e in Ash.Error.Forbidden -> e
      end
    end
  end
end
