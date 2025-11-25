defmodule Triage.RunTest do
  use ExUnit.Case

  setup do
    Process.put(:error_count_agent_id, System.unique_integer([:positive]))

    :ok
  end

  describe("run!/1") do
    test "Returns term as success" do
      start = 123
      assert Triage.run!(fn -> start * 2 end) == {:ok, 246}
    end

    test "Returns :ok as :ok" do
      assert Triage.run!(fn -> :ok end) == :ok
    end

    test "Returns success with value as success" do
      start = 123
      assert Triage.run!(fn -> {:ok, start * 2} end) == {:ok, 246}
    end

    test "Returns :error as :error" do
      assert Triage.run!(fn -> :error end) == :error
    end

    test "Returns error with value as error" do
      assert Triage.run!(fn -> {:error, "Test error"} end) == {:error, "Test error"}
    end

    test "Supports 3+ values :ok tuples returns from function" do
      assert Triage.run!(fn -> {:ok, :foo, :bar} end) == {:ok, :foo, :bar}
    end

    test "Supports 3+ values :error tuples returns from function" do
      assert Triage.run!(fn -> {:error, :foo, :bar} end) == {:error, :foo, :bar}
    end
  end

  describe "run/1" do
    test "Returns term as success" do
      start = 123
      assert Triage.run(fn -> start * 2 end) == {:ok, 246}
    end

    test "Returns :ok as :ok" do
      assert Triage.run(fn -> :ok end) == :ok
    end

    test "Returns success with value as success" do
      start = 123
      assert Triage.run(fn -> {:ok, start * 2} end) == {:ok, 246}
    end

    test "Returns :error as :error" do
      assert Triage.run(fn -> :error end) == :error
    end

    test "Returns error with value as error" do
      assert Triage.run(fn -> {:error, "Test error"} end) == {:error, "Test error"}
    end

    test "An exception is raised" do
      {:error, %Triage.WrappedError{} = wrapped_error} =
        Triage.run(fn -> raise "boom" end)

      assert wrapped_error.message =~
               ~r<\*\* \(RuntimeError\) boom\n    \[CONTEXT\] test/triage/run_test\.exs:\d+: Triage\.RunTest\.-test run/1 An exception is raised/1-fun-0-/1>

      assert wrapped_error.result == %RuntimeError{message: "boom"}
    end

    test "Supports 3+ values :ok tuples returns from function" do
      assert Triage.run(fn -> {:ok, :foo, :bar} end) == {:ok, :foo, :bar}
    end

    test "Supports 3+ values :error tuples returns from function" do
      assert Triage.run(fn -> {:error, :foo, :bar} end) == {:error, :foo, :bar}
    end
  end

  def error_count_agent do
    id = Process.get(:error_count_agent_id)

    :"error_count_agent_#{id}"
  end

  def fn_fails_times(number_of_errors, error, ok_value) do
    fn -> fails_times(number_of_errors, error, ok_value) end
  end

  def fails_times(number_of_errors, error, ok_value) do
    error_so_far = Agent.get_and_update(error_count_agent(), fn c -> {c, c + 1} end)

    if error_so_far < number_of_errors do
      if is_function(error) do
        error.()
      else
        error
      end
    else
      ok_value
    end
  end

  describe "run!/2 with retries option" do
    setup do
      # Agent to track error count
      {:ok, _} = Agent.start_link(fn -> 0 end, name: error_count_agent())

      :ok
    end

    test "retries invalid values" do
      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: "0"),
                   fn ->
                     Triage.run!(fn -> {:ok, "success"} end,
                       retries: "0"
                     )
                   end

      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: 3.14),
                   fn ->
                     Triage.run!(fn -> {:ok, "success"} end,
                       retries: 3.14
                     )
                   end

      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: nil),
                   fn ->
                     Triage.run!(fn -> {:ok, "success"} end,
                       retries: nil
                     )
                   end
    end

    test "retries: 0 - returns success immediately without retrying" do
      result =
        Triage.run!(
          fn ->
            {:ok, "success"}
          end,
          retries: 0
        )

      assert result == {:ok, "success"}
    end

    test "retries: 0 - returns error immediately without retrying" do
      result =
        Triage.run!(
          fn ->
            {:error, "failure"}
          end,
          retries: 0
        )

      assert result == {:error, "failure"}
    end

    test "retries: 1 - fails 1 times - atoms" do
      result =
        Triage.run!(
          fn_fails_times(1, :error, :ok),
          retries: 1
        )

      assert result == :ok
    end

    test "retries: 1 - fails 1 times - tuples" do
      result =
        Triage.run!(
          fn_fails_times(1, {:error, "failure"}, {:ok, "yay!"}),
          retries: 1
        )

      assert result == {:ok, "yay!"}
    end

    test "retries: 1 - fails 1 times - exception" do
      assert_raise RuntimeError, "this should not be caught", fn ->
        Triage.run!(
          fn_fails_times(1, fn -> raise "this should not be caught" end, :ok),
          retries: 1
        )
      end
    end

    test "retries: 1 - fails 2 times - atoms" do
      result =
        Triage.run!(
          fn_fails_times(2, :error, :ok),
          retries: 1
        )

      assert result == :error
    end

    test "retries: 1 - fails 2 times - tuples" do
      result =
        Triage.run!(
          fn_fails_times(2, {:error, "failure"}, {:ok, "yay!"}),
          retries: 1
        )

      assert result == {:error, "failure"}
    end

    test "retries: 5 - fails 5 times - atoms" do
      result =
        Triage.run!(
          fn_fails_times(5, :error, :ok),
          retries: 5
        )

      assert result == :ok
    end

    test "retries: 5 - fails 5 times - tuples" do
      result =
        Triage.run!(
          fn_fails_times(5, {:error, "failure"}, {:ok, "yay!"}),
          retries: 5
        )

      assert result == {:ok, "yay!"}
    end

    test "retries: 5 - fails 6 times - atoms" do
      result =
        Triage.run!(
          fn_fails_times(6, :error, :ok),
          retries: 5
        )

      assert result == :error
    end

    test "retries: 5 - fails 6 times - tuples" do
      result =
        Triage.run!(
          fn_fails_times(6, {:error, "failure"}, {:ok, "yay!"}),
          retries: 5
        )

      assert result == {:error, "failure"}
    end
  end

  describe "run/2 with retries option" do
    setup do
      # Agent to track error count
      {:ok, _} = Agent.start_link(fn -> 0 end, name: error_count_agent())

      :ok
    end

    test "retries invalid values" do
      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: "0"),
                   fn ->
                     Triage.run(fn -> {:ok, "success"} end,
                       retries: "0"
                     )
                   end

      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: 3.14),
                   fn ->
                     Triage.run(fn -> {:ok, "success"} end,
                       retries: 3.14
                     )
                   end

      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: nil),
                   fn ->
                     Triage.run(fn -> {:ok, "success"} end,
                       retries: nil
                     )
                   end
    end

    test "retries: 0 - returns success immediately without retrying" do
      result =
        Triage.run(
          fn ->
            {:ok, "success"}
          end,
          retries: 0
        )

      assert result == {:ok, "success"}
    end

    test "retries: 0 - returns error immediately without retrying" do
      result =
        Triage.run(
          fn ->
            {:error, "failure"}
          end,
          retries: 0
        )

      assert result == {:error, "failure"}
    end

    test "retries: 1 - fails 1 times - atoms" do
      result =
        Triage.run(
          fn_fails_times(1, :error, :ok),
          retries: 1
        )

      assert result == :ok
    end

    test "retries: 1 - fails 1 times - tuples" do
      result =
        Triage.run(
          fn_fails_times(1, {:error, "failure"}, {:ok, "yay!"}),
          retries: 1
        )

      assert result == {:ok, "yay!"}
    end

    test "retries: 1 - fails 1 times - exception" do
      result =
        Triage.run(
          fn_fails_times(1, fn -> raise "this should be caught" end, :ok),
          retries: 1
        )

      assert result == :ok
    end

    test "retries: 1 - fails 2 times - atoms" do
      result =
        Triage.run(
          fn_fails_times(2, :error, :ok),
          retries: 1
        )

      assert result == :error
    end

    test "retries: 1 - fails 2 times - tuples" do
      result =
        Triage.run(
          fn_fails_times(2, {:error, "failure"}, {:ok, "yay!"}),
          retries: 1
        )

      assert result == {:error, "failure"}
    end

    test "retries: 1 - fails 2 times - exception" do
      {:error, %Triage.WrappedError{} = wrapped_error} =
        Triage.run(
          fn_fails_times(2, fn -> raise "this should be caught" end, :ok),
          retries: 1
        )

      assert wrapped_error.message =~
               ~r<\*\* \(RuntimeError\) this should be caught\n    \[CONTEXT\] test/triage/run_test\.exs:\d+: Triage\.RunTest\.-fn_fails_times/3-fun-0-/1>

      assert wrapped_error.result == %RuntimeError{message: "this should be caught"}
    end

    test "retries: 5 - fails 5 times - atoms" do
      result =
        Triage.run(
          fn_fails_times(5, :error, :ok),
          retries: 5
        )

      assert result == :ok
    end

    test "retries: 5 - fails 5 times - tuples" do
      result =
        Triage.run(
          fn_fails_times(5, {:error, "failure"}, {:ok, "yay!"}),
          retries: 5
        )

      assert result == {:ok, "yay!"}
    end

    test "retries: 5 - fails 6 times - atoms" do
      result =
        Triage.run(
          fn_fails_times(6, :error, :ok),
          retries: 5
        )

      assert result == :error
    end

    test "retries: 5 - fails 6 times - tuples" do
      result =
        Triage.run(
          fn_fails_times(6, {:error, "failure"}, {:ok, "yay!"}),
          retries: 5
        )

      assert result == {:error, "failure"}
    end
  end
end
