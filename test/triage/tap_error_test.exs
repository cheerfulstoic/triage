defmodule Triage.TapErrorTest do
  use ExUnit.Case

  describe "tap_error/2" do
    test "only allows result values for first argument" do
      assert_raise ArgumentError,
                   "Argument must be {:ok, _} / :ok / {:error, _} / :error, got: 321",
                   fn ->
                     Triage.tap_error(321, fn _ -> raise "should not run" end)
                   end

      assert_raise ArgumentError,
                   "Argument must be {:ok, _} / :ok / {:error, _} / :error, got: :eror",
                   fn ->
                     Triage.tap_error(:eror, fn _ -> raise "should not run" end)
                   end
    end

    test "ignores and passes through ok results" do
      assert Triage.tap_error(:ok, fn _ -> raise "should not run" end) == :ok

      assert Triage.tap_error({:ok, :the_value}, fn _ -> raise "should not run" end) ==
               {:ok, :the_value}
    end

    test "runs the function for error results" do
      thrown =
        catch_throw(assert Triage.tap_error(:error, fn nil -> throw("got nil!") end) == :error)

      assert thrown == "got nil!"

      thrown =
        catch_throw(
          assert Triage.tap_error({:error, :reason}, fn value ->
                   throw("got #{inspect(value)}!")
                 end) ==
                   {:error, :reason}
        )

      assert thrown == "got :reason!"
    end
  end
end
