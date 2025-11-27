defmodule Triage.IntegrationTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  setup do
    Application.delete_env(:triage, :app)
    Application.delete_env(:triage, :log_adapter)

    on_exit(fn ->
      Application.delete_env(:triage, :app)
      Application.delete_env(:triage, :log_adapter)
    end)

    :ok
  end

  describe "run!/1 + ok_then!/2 with wrap_context" do
    test "wraps error with context" do
      result =
        Triage.run!(fn -> {:error, "database connection failed"} end)
        |> Triage.wrap_context("Fetching user")

      assert {:error, %Triage.WrappedError{} = wrapped_error} = result
      assert wrapped_error.context == "Fetching user"
      assert wrapped_error.metadata == %{}
      assert wrapped_error.result == {:error, "database connection failed"}
    end

    test "wraps error in multi-then chain" do
      result =
        Triage.run!(fn -> {:ok, 10} end)
        |> Triage.ok_then!(fn _ -> {:error, "calculation failed"} end)
        |> Triage.ok_then!(fn _ -> raise "Should not be called" end)
        |> Triage.wrap_context("Final calculation")

      assert {:error, %Triage.WrappedError{} = wrapped_error} = result
      assert wrapped_error.context == "Final calculation"
      assert wrapped_error.metadata == %{}
      assert wrapped_error.result == {:error, "calculation failed"}
    end
  end

  describe "ok_then!/2 with wrap_context" do
    test "wraps error with context" do
      result =
        {:error, "user not found"}
        |> Triage.ok_then!(fn _ -> raise "Should not be called" end)
        |> Triage.wrap_context("Fetching user")

      assert {:error, %Triage.WrappedError{} = wrapped_error} = result
      assert wrapped_error.context == "Fetching user"
      assert wrapped_error.metadata == %{}
      assert wrapped_error.result == {:error, "user not found"}
    end

    test "chains multiple wrap_context calls" do
      result =
        {:ok, "user@example.com"}
        |> Triage.ok_then!(fn email -> {:error, "invalid email: #{email}"} end)
        |> Triage.wrap_context("first")
        |> Triage.ok_then!(fn _ -> raise "Should not be called" end)
        |> Triage.wrap_context("second")

      assert {:error, %Triage.WrappedError{} = wrapped_error} = result
      assert wrapped_error.context == "second"
      assert wrapped_error.metadata == %{}

      assert {:error, %Triage.WrappedError{} = second_wrapped_error} = wrapped_error.result
      assert second_wrapped_error.context == "first"
      assert second_wrapped_error.metadata == %{}
      assert second_wrapped_error.result == {:error, "invalid email: user@example.com"}
    end
  end

  describe "ok_then/2 with wrap_context" do
    test "wraps caught exception with context" do
      func = fn _ -> raise ArgumentError, "invalid value" end

      result =
        {:ok, 10}
        |> Triage.ok_then(func)
        |> Triage.wrap_context("Processing payment")

      assert {:error, %Triage.WrappedError{} = wrapped_error} = result
      assert wrapped_error.context == "Processing payment"
      assert wrapped_error.metadata == %{}

      assert {:error, %Triage.WrappedError{} = second_wrapped_error} = wrapped_error.result
      assert second_wrapped_error.context == func
      assert second_wrapped_error.metadata == %{}

      assert {Triage.IntegrationTest,
              :"-test ok_then/2 with wrap_context wraps caught exception with context/1-fun-0-",
              _, [file: ~c"test/triage/integration_test.exs", line: _]} =
               List.first(second_wrapped_error.stacktrace)

      assert %ArgumentError{message: "invalid value"} = second_wrapped_error.result
    end

    test "wraps error with context" do
      result =
        {:error, "user not found"}
        |> Triage.ok_then(fn _ -> raise "Should not be called" end)
        |> Triage.wrap_context("Fetching user")

      assert {:error, %Triage.WrappedError{} = wrapped_error} = result
      assert wrapped_error.context == "Fetching user"
      assert wrapped_error.metadata == %{}
      assert wrapped_error.result == {:error, "user not found"}
    end

    test "chains multiple wrap_context calls" do
      result =
        {:ok, "user@example.com"}
        |> Triage.ok_then(fn email -> {:error, "invalid email: #{email}"} end)
        |> Triage.wrap_context("first")
        |> Triage.ok_then(fn _ -> raise "Should not be called" end)
        |> Triage.wrap_context("second")

      assert {:error, %Triage.WrappedError{} = wrapped_error} = result
      assert wrapped_error.context == "second"
      assert wrapped_error.metadata == %{}

      assert {:error, %Triage.WrappedError{} = second_wrapped_error} = wrapped_error.result
      assert second_wrapped_error.context == "first"
      assert second_wrapped_error.metadata == %{}
      assert second_wrapped_error.result == {:error, "invalid email: user@example.com"}
    end
  end

  describe "log with wrapped errors" do
    test "logs simple wrapped error with context" do
      log =
        capture_log([level: :error], fn ->
          result =
            Triage.run!(fn -> {:error, "database timeout"} end)
            |> Triage.wrap_context("Fetching user data")
            |> Triage.log()

          assert {:error, %Triage.WrappedError{}} = result
        end)

      assert log =~
               ~r<\[RESULT\] test/triage/integration_test\.exs:\d+: {:error, "database timeout"}
    \[CONTEXT\] test/triage/integration_test\.exs:\d+: Fetching user data>
    end

    test "logs nested wrapped errors from ok_then/2 exception" do
      log =
        capture_log([level: :error], fn ->
          result =
            {:ok, 100}
            |> Triage.ok_then(&Triage.TestHelper.raise_argument_error/1)
            |> Triage.wrap_context("Processing payment")
            |> Triage.log()

          assert {:error, %Triage.WrappedError{}} = result
        end)

      assert log =~
               ~r<\[RESULT\] test/triage/integration_test\.exs:\d+: \*\* \(ArgumentError\) amount too high
    \[CONTEXT\] test/triage/integration_test\.exs:\d+: Processing payment
    \[CONTEXT\] lib/triage/test_helper.ex:\d+: Triage\.TestHelper\.raise_argument_error/1>
    end

    test "logs deeply nested contexts" do
      log =
        capture_log([level: :error], fn ->
          result =
            {:ok, "test@example.com"}
            |> Triage.ok_then!(fn email -> {:error, "invalid domain for #{email}"} end)
            |> Triage.wrap_context("Validating email")
            |> Triage.wrap_context("User registration")
            |> Triage.wrap_context("API endpoint: /users")
            |> Triage.log()

          assert {:error, %Triage.WrappedError{}} = result
        end)

      assert log =~
               ~r<\[RESULT\] test/triage/integration_test\.exs:\d+: {:error, "invalid domain for test@example.com"}
    \[CONTEXT\] test/triage/integration_test\.exs:\d+: API endpoint: /users
    \[CONTEXT\] test/triage/integration_test\.exs:\d+: User registration
    \[CONTEXT\] test/triage/integration_test\.exs:\d+: Validating email>
    end

    test "does not log successes with :errors mode" do
      log =
        capture_log([level: :error], fn ->
          result = {:ok, "success"} |> Triage.log()
          assert result == {:ok, "success"}
        end)

      assert log == ""
    end

    test "logs successes with :all mode" do
      log =
        capture_log([level: :info], fn ->
          result = {:ok, 42} |> Triage.log(mode: :all)
          assert result == {:ok, 42}
        end)

      assert log =~ ~r<\[RESULT\] test/triage/integration_test\.exs:\d+: {:ok, 42}>
    end

    test "logs ok_then/2 chain with exception and wrap_context" do
      log =
        capture_log([level: :error], fn ->
          result =
            {:ok, 5}
            |> Triage.ok_then(fn x -> x * 2 end)
            |> Triage.ok_then(fn x -> x + 3 end)
            |> Triage.ok_then(fn _ -> raise RuntimeError, "unexpected failure" end)
            |> Triage.wrap_context("Data processing pipeline")
            |> Triage.log()

          assert {:error, %Triage.WrappedError{}} = result
        end)

      assert log =~
               ~r<\[RESULT\] test/triage/integration_test\.exs:\d+: \*\* \(RuntimeError\) unexpected failure
    \[CONTEXT\] test/triage/integration_test\.exs:\d+: Data processing pipeline
    \[CONTEXT\] test/triage/integration_test\.exs:\d+: Triage\.IntegrationTest\.-test log with wrapped errors logs ok_then/2 chain with exception and wrap_context/1-fun-0-/1>
    end
  end

  # test "" do
  #   log =
  #     capture_log([level: :error], fn ->
  #       {:ok, "123u"}
  #       # Raises if not a valid integer
  #       |> Triage.ok_then(&String.to_integer/1)
  #       |> Triage.log()
  #     end)
  #
  #   assert log =~
  #            ~r<\[RESULT\] lib/ex_unit/capture_log\.ex:\d+: \*\* \(ArgumentError\) errors were found at the given arguments:
  #
  # \* 1st argument: not a textual representation of an integer
  #
  #   \[CONTEXT\] :erlang\.binary_to_integer/1>
  #
  #   Application.put_env(:triage, :log_adapter, Triage.LogAdapter.JSON)
  #
  #   log =
  #     capture_log([level: :error], fn ->
  #       {:ok, "123u"}
  #       # Raises if not a valid integer
  #       |> Triage.ok_then(&String.to_integer/1)
  #       |> Triage.log()
  #     end)
  #
  #   [_, json] = Regex.run(~r/\[error\] (.*)/, log)
  #
  #   data = Jason.decode!(json)
  #
  #   assert data["source"] == "Triage"
  #   assert data["stacktrace_line"] =~ ~r[^lib/ex_unit/capture_log\.ex:\d+$]
  #
  #   assert data["result_details"]["type"] == "error"
  #
  #   assert data["result_details"]["message"] ==
  #            "** (ArgumentError) errors were found at the given arguments:\n\n  * 1st argument: not a textual representation of an integer\n\n    [CONTEXT] :erlang.binary_to_integer/1"
  #
  #   assert %{
  #            "__struct__" => "ArgumentError",
  #            "__message__" =>
  #              "errors were found at the given arguments:\n\n  * 1st argument: not a textual representation of an integer\n"
  #          } = data["result_details"]["value"]["__root_reason__"]
  # end
end
