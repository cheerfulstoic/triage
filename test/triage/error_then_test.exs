defmodule Triage.ErrorThenTest do
  use ExUnit.Case

  describe "error_then/1" do
    test "requires result to be a result" do
      func = fn :unknown -> :not_found end

      assert_raise ArgumentError,
                   "Argument must be {:ok, _} / :ok / {:error, _} / :error, got: :ook",
                   fn ->
                     Triage.error_then(:ook, func) == :ok
                   end

      assert_raise ArgumentError,
                   "Argument must be {:ok, _} / :ok / {:error, _} / :error, got: 123",
                   fn ->
                     Triage.error_then(123, func) == :ok
                   end

      assert_raise ArgumentError,
                   "Argument must be {:ok, _} / :ok / {:error, _} / :error, got: {:wow, 246}",
                   fn ->
                     Triage.error_then({:wow, 246}, func) == {:ok, 246}
                   end
    end

    test "passes through successes unchanged" do
      func = fn :unknown -> :not_found end

      assert Triage.error_then(:ok, func) == :ok
      assert Triage.error_then({:ok, 246}, func) == {:ok, 246}
    end

    test ":error atom" do
      func = fn
        :unknown -> :not_found
        :server_timed_out -> :timeout
        nil -> :wow_nil_cool
      end

      assert Triage.error_then(:error, func) == {:error, :wow_nil_cool}

      func = fn
        :unknown -> :not_found
        :server_timed_out -> :timeout
      end

      assert_raise FunctionClauseError, fn ->
        Triage.error_then(:error, func)
      end
    end

    test "nil returned from callback - returns :error" do
      func = fn _ -> nil end

      assert Triage.error_then({:error, "something"}, func) == :error
    end

    test "error tuples are handled by the callback" do
      func = fn
        :unknown -> :not_found
        :server_timed_out -> :timeout
      end

      assert Triage.error_then({:error, :unknown}, func) == {:error, :not_found}
      assert Triage.error_then({:error, :server_timed_out}, func) == {:error, :timeout}

      assert_raise FunctionClauseError, fn ->
        Triage.error_then({:error, :something_else}, func)
      end
    end

    test "returning success results on error" do
      func = fn
        :unknown -> :not_found
        :server_timed_out -> {:ok, :default_value}
        :whatever -> :ok
      end

      assert Triage.error_then({:error, :unknown}, func) == {:error, :not_found}
      assert Triage.error_then({:error, :server_timed_out}, func) == {:ok, :default_value}
      assert Triage.error_then({:error, :whatever}, func) == :ok
    end

    test "Supports 3+ values :ok tuples returns from function" do
      assert Triage.error_then(:error, fn _ -> {:ok, :foo, :bar} end) == {:ok, :foo, :bar}
    end

    test "Supports 3+ values :error tuples returns from function" do
      assert Triage.error_then(:error, fn _ -> {:error, :foo, :bar} end) == {:error, :foo, :bar}
    end
  end
end
