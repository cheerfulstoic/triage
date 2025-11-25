defmodule Triage.OkThenTest do
  use ExUnit.Case

  setup do
    Process.put(:error_count_agent_id, System.unique_integer([:positive]))

    :ok
  end

  describe "ok_then!/2" do
    test "only allows result values for first argument" do
      assert_raise ArgumentError,
                   "Argument must be {:ok, _} / :ok / {:error, _} / :error, got: 321",
                   fn ->
                     Triage.ok_then!(321, fn _ -> 123 end)
                   end

      assert_raise ArgumentError,
                   "Argument must be {:ok, _} / :ok / {:error, _} / :error, got: :eror",
                   fn ->
                     Triage.ok_then!(:eror, fn _ -> 123 end)
                   end
    end

    test "passes value from {:ok, term} to function" do
      result = {:ok, 10}
      assert Triage.ok_then!(result, fn x -> x * 2 end) == {:ok, 20}
    end

    test "passes nil to function when given :ok" do
      result = :ok
      assert Triage.ok_then!(result, fn nil -> 42 end) == {:ok, 42}
    end

    test "returns :error without calling function" do
      result = :error
      assert Triage.ok_then!(result, fn _ -> raise "Should not be called" end) == :error
    end

    test "returns {:error, term} without calling function" do
      result = {:error, "some error"}

      assert Triage.ok_then!(result, fn _ -> raise "Should not be called" end) ==
               {:error, "some error"}
    end

    test "passes through :ok from function" do
      result = {:ok, 5}
      assert Triage.ok_then!(result, fn 5 -> :ok end) == :ok
    end

    test "passes through :error from function" do
      result = {:ok, 5}
      assert Triage.ok_then!(result, fn 5 -> :error end) == :error
    end

    test "passes through {:error, _} from function" do
      result = {:ok, 5}
      assert Triage.ok_then!(result, fn _ -> {:error, "failed"} end) == {:error, "failed"}
    end

    test "chains multiple ok_then! calls" do
      result =
        {:ok, 10}
        |> Triage.ok_then!(fn x -> x + 5 end)
        |> Triage.ok_then!(fn x -> x * 2 end)
        |> Triage.ok_then!(fn x -> x - 10 end)

      assert result == {:ok, 20}
    end

    test "stops chain on error" do
      result =
        {:ok, 10}
        |> Triage.ok_then!(fn x -> x + 5 end)
        |> Triage.ok_then!(fn 15 -> {:error, "oops"} end)
        |> Triage.ok_then!(fn _ -> raise "Should not be called" end)

      assert result == {:error, "oops"}
    end

    test "does not catch exceptions" do
      assert_raise RuntimeError, "The raised error", fn ->
        {:ok, 10}
        |> Triage.ok_then!(fn x -> x + 5 end)
        |> Triage.ok_then!(fn _ -> raise "The raised error" end)
        |> Triage.ok_then!(fn _ -> raise "Should not be called" end)
      end
    end

    test "handles :ok in chain" do
      result =
        {:ok, 10}
        |> Triage.ok_then!(fn _ -> :ok end)
        |> Triage.ok_then!(fn nil -> 42 end)

      assert result == {:ok, 42}
    end

    test "Supports 3+ values :ok tuples returns from function" do
      assert Triage.ok_then!(:ok, fn _ -> {:ok, :foo, :bar} end) == {:ok, :foo, :bar}
    end

    test "Supports 3+ values :error tuples returns from function" do
      assert Triage.ok_then!(:ok, fn _ -> {:error, :foo, :bar} end) == {:error, :foo, :bar}
    end
  end

  describe "ok_then/2" do
    test "behaves like ok_then!/2 for successful operations" do
      result = {:ok, 10}
      assert Triage.ok_then(result, fn x -> x * 2 end) == {:ok, 20}
    end

    test "passes nil to function when given :ok" do
      result = :ok
      assert Triage.ok_then(result, fn nil -> 42 end) == {:ok, 42}
    end

    test "returns :error without calling function" do
      result = :error
      assert Triage.ok_then(result, fn _ -> raise "Should not be called" end) == :error
    end

    test "returns {:error, term} without calling function" do
      result = {:error, "some error"}

      assert Triage.ok_then(result, fn _ -> raise "Should not be called" end) ==
               {:error, "some error"}
    end

    test "catches exceptions and wraps them in WrappedError" do
      result = {:ok, 10}

      {:error, %Triage.WrappedError{} = wrapped_error} =
        Triage.ok_then(result, fn _ -> raise "boom" end)

      assert wrapped_error.result == %RuntimeError{message: "boom"}
    end

    test "chains multiple then calls" do
      result =
        {:ok, 10}
        |> Triage.ok_then(fn x -> x + 5 end)
        |> Triage.ok_then(fn x -> x * 2 end)
        |> Triage.ok_then(fn x -> x - 10 end)

      assert result == {:ok, 20}
    end

    test "stops chain on error" do
      result =
        {:ok, 10}
        |> Triage.ok_then(fn x -> x + 5 end)
        |> Triage.ok_then(fn 15 -> {:error, "oops"} end)
        |> Triage.ok_then(fn _ -> raise "Should not be called" end)

      assert result == {:error, "oops"}
    end

    test "catches exception and stops chain" do
      result =
        {:ok, 10}
        |> Triage.ok_then(fn x -> x + 5 end)
        |> Triage.ok_then(fn _ -> raise "boom" end)
        |> Triage.ok_then(fn _ -> raise "Should not be called" end)

      assert {:error, %Triage.WrappedError{result: %RuntimeError{message: "boom"}}} =
               result
    end

    test "catches ArgumentError" do
      result = Triage.ok_then({:ok, "test"}, fn _ -> raise ArgumentError, "invalid argument" end)

      assert {:error, %Triage.WrappedError{result: %ArgumentError{message: "invalid argument"}}} =
               result
    end

    test "catches custom exceptions" do
      defmodule CustomError do
        defexception message: "custom error"
      end

      assert {:error, %Triage.WrappedError{result: reason}} =
               Triage.ok_then({:ok, 5}, fn _ -> raise CustomError end)

      assert reason.__struct__ == CustomError
      assert reason.message == "custom error"
    end

    test "Supports 3+ values :ok tuples returns from function" do
      assert Triage.ok_then(:ok, fn _ -> {:ok, :foo, :bar} end) == {:ok, :foo, :bar}
    end

    test "Supports 3+ values :error tuples returns from function" do
      assert Triage.ok_then(:ok, fn _ -> {:error, :foo, :bar} end) == {:error, :foo, :bar}
    end
  end

  def error_count_agent do
    id = Process.get(:error_count_agent_id)

    :"error_count_agent_#{id}"
  end

  def fn_fails_times(number_of_errors, error, ok_value) do
    # We don't care about the input when testing for retries
    fn _ -> fails_times(number_of_errors, error, ok_value) end
  end

  def fails_times(number_of_errors, error, ok_value) do
    id = Process.get(:error_count_agent_id)

    error_so_far = Agent.get_and_update(:"error_count_agent_#{id}", fn c -> {c, c + 1} end)

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

  describe "ok_then!/3 with retries option" do
    setup do
      # Agent to track error count
      {:ok, _} = Agent.start_link(fn -> 0 end, name: error_count_agent())

      :ok
    end

    test "retries invalid values" do
      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: "0"),
                   fn ->
                     Triage.ok_then!(:ok, fn _ -> {:ok, "success"} end, retries: "0")
                   end

      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: 3.14),
                   fn ->
                     Triage.ok_then!(:ok, fn _ -> {:ok, "success"} end, retries: 3.14)
                   end

      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: nil),
                   fn ->
                     Triage.ok_then!(:ok, fn _ -> {:ok, "success"} end, retries: nil)
                   end
    end

    test "retries: 0 - returns success immediately without retrying" do
      result =
        Triage.ok_then!(
          :ok,
          fn _ ->
            {:ok, "success"}
          end,
          retries: 0
        )

      assert result == {:ok, "success"}
    end

    test "retries: 0 - returns error immediately without retrying" do
      result =
        Triage.ok_then!(
          :ok,
          fn _ ->
            {:error, "failure"}
          end,
          retries: 0
        )

      assert result == {:error, "failure"}
    end

    test "retries: 1 - fails 1 times - atoms" do
      result =
        Triage.ok_then!(
          :ok,
          fn_fails_times(1, :error, :ok),
          retries: 1
        )

      assert result == :ok
    end

    test "retries: 1 - fails 1 times - tuples" do
      result =
        Triage.ok_then!(
          :ok,
          fn_fails_times(1, {:error, "failure"}, {:ok, "yay!"}),
          retries: 1
        )

      assert result == {:ok, "yay!"}
    end

    test "retries: 1 - fails 1 times - exception" do
      assert_raise RuntimeError, "this should not be caught", fn ->
        Triage.ok_then!(
          :ok,
          fn_fails_times(1, fn -> raise "this should not be caught" end, :ok),
          retries: 1
        )
      end
    end

    test "retries: 1 - fails 2 times - atoms" do
      result =
        Triage.ok_then!(
          :ok,
          fn_fails_times(2, :error, :ok),
          retries: 1
        )

      assert result == :error
    end

    test "retries: 1 - fails 2 times - tuples" do
      result =
        Triage.ok_then!(
          :ok,
          fn_fails_times(2, {:error, "failure"}, {:ok, "yay!"}),
          retries: 1
        )

      assert result == {:error, "failure"}
    end

    test "retries: 5 - fails 5 times - atoms" do
      result =
        Triage.ok_then!(
          :ok,
          fn_fails_times(5, :error, :ok),
          retries: 5
        )

      assert result == :ok
    end

    test "retries: 5 - fails 5 times - tuples" do
      result =
        Triage.ok_then!(
          :ok,
          fn_fails_times(5, {:error, "failure"}, {:ok, "yay!"}),
          retries: 5
        )

      assert result == {:ok, "yay!"}
    end

    test "retries: 5 - fails 6 times - atoms" do
      result =
        Triage.ok_then!(
          :ok,
          fn_fails_times(6, :error, :ok),
          retries: 5
        )

      assert result == :error
    end

    test "retries: 5 - fails 6 times - tuples" do
      result =
        Triage.ok_then!(
          :ok,
          fn_fails_times(6, {:error, "failure"}, {:ok, "yay!"}),
          retries: 5
        )

      assert result == {:error, "failure"}
    end
  end

  describe "ok_then/3 with retries option" do
    setup do
      # Agent to track error count
      {:ok, _} = Agent.start_link(fn -> 0 end, name: error_count_agent())

      :ok
    end

    test "retries invalid values" do
      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: "0"),
                   fn ->
                     Triage.ok_then(:ok, fn _ -> {:ok, "success"} end, retries: "0")
                   end

      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: 3.14),
                   fn ->
                     Triage.ok_then(:ok, fn _ -> {:ok, "success"} end, retries: 3.14)
                   end

      assert_raise ArgumentError,
                   ~s(invalid value for :retries option: expected non negative integer, got: nil),
                   fn ->
                     Triage.ok_then(:ok, fn _ -> {:ok, "success"} end, retries: nil)
                   end
    end

    test "retries: 0 - returns success immediately without retrying" do
      result =
        Triage.ok_then(
          :ok,
          fn _ ->
            {:ok, "success"}
          end,
          retries: 0
        )

      assert result == {:ok, "success"}
    end

    test "retries: 0 - returns error immediately without retrying" do
      result =
        Triage.ok_then(
          :ok,
          fn _ ->
            {:error, "failure"}
          end,
          retries: 0
        )

      assert result == {:error, "failure"}
    end

    test "retries: 1 - fails 1 times - atoms" do
      result =
        Triage.ok_then(
          :ok,
          fn_fails_times(1, :error, :ok),
          retries: 1
        )

      assert result == :ok
    end

    test "retries: 1 - fails 1 times - tuples" do
      result =
        Triage.ok_then(
          :ok,
          fn_fails_times(1, {:error, "failure"}, {:ok, "yay!"}),
          retries: 1
        )

      assert result == {:ok, "yay!"}
    end

    test "retries: 1 - fails 1 times - exception" do
      result =
        Triage.ok_then(
          :ok,
          fn_fails_times(1, fn -> raise "this should be caught" end, :ok),
          retries: 1
        )

      assert result == :ok
    end

    test "retries: 1 - fails 2 times - atoms" do
      result =
        Triage.ok_then(
          :ok,
          fn_fails_times(2, :error, :ok),
          retries: 1
        )

      assert result == :error
    end

    test "retries: 1 - fails 2 times - tuples" do
      result =
        Triage.ok_then(
          :ok,
          fn_fails_times(2, {:error, "failure"}, {:ok, "yay!"}),
          retries: 1
        )

      assert result == {:error, "failure"}
    end

    test "retries: 1 - fails 2 times - exception" do
      {:error, %Triage.WrappedError{} = wrapped_error} =
        Triage.ok_then(
          :ok,
          fn_fails_times(2, fn -> raise "this should be caught" end, :ok),
          retries: 1
        )

      assert wrapped_error.message =~
               ~r<\*\* \(RuntimeError\) this should be caught\n    \[CONTEXT\] test/triage/ok_then_test\.exs:\d+: Triage\.OkThenTest\.-fn_fails_times/3-fun-0-/1>

      assert wrapped_error.result == %RuntimeError{message: "this should be caught"}
    end

    test "retries: 5 - fails 5 times - atoms" do
      result =
        Triage.ok_then(
          :ok,
          fn_fails_times(5, :error, :ok),
          retries: 5
        )

      assert result == :ok
    end

    test "retries: 5 - fails 5 times - tuples" do
      result =
        Triage.ok_then(
          :ok,
          fn_fails_times(5, {:error, "failure"}, {:ok, "yay!"}),
          retries: 5
        )

      assert result == {:ok, "yay!"}
    end

    test "retries: 5 - fails 6 times - atoms" do
      result =
        Triage.ok_then(
          :ok,
          fn_fails_times(6, :error, :ok),
          retries: 5
        )

      assert result == :error
    end

    test "retries: 5 - fails 6 times - tuples" do
      result =
        Triage.ok_then(
          :ok,
          fn_fails_times(6, {:error, "failure"}, {:ok, "yay!"}),
          retries: 5
        )

      assert result == {:error, "failure"}
    end
  end
end
