defmodule Triage.TapOkTest do
  use ExUnit.Case

  describe "tap_ok/2" do
    test "only allows result values for first argument" do
      assert_raise ArgumentError,
                   "Argument must be {:ok, _} / :ok / {:error, _} / :error, got: 321",
                   fn ->
                     Triage.tap_ok(321, fn _ -> raise "should not run" end)
                   end

      assert_raise ArgumentError,
                   "Argument must be {:ok, _} / :ok / {:error, _} / :error, got: :eror",
                   fn ->
                     Triage.tap_ok(:eror, fn _ -> raise "should not run" end)
                   end
    end

    test "ignores and passes through error results" do
      assert Triage.tap_ok(:error, fn _ -> raise "should not run" end) == :error

      assert Triage.tap_ok({:error, :reason}, fn _ -> raise "should not run" end) ==
               {:error, :reason}
    end

    test "runs the function for ok results" do
      thrown =
        catch_throw(assert Triage.tap_ok(:ok, fn nil -> throw("got nil!") end) == :ok)

      assert thrown == "got nil!"

      thrown =
        catch_throw(
          assert Triage.tap_ok({:ok, :the_value}, fn value -> throw("got #{inspect(value)}!") end) ==
                   {:ok, :the_value}
        )

      assert thrown == "got :the_value!"
    end
  end
end
