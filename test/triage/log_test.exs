defmodule Triage.LogTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  require Logger

  defmodule CustomStruct do
    defstruct [:id, :foo, :user_id, :bar]
  end

  defmodule OtherCustomStruct do
    defstruct [:id, :name, :something, :fooID]
  end

  defmodule CustomError do
    defexception [:message]
  end

  defmodule User do
    use Ecto.Schema

    embedded_schema do
      field(:name, :string)
    end
  end

  setup do
    Application.delete_env(:triage, :app)
    Application.delete_env(:triage, :log_adapter)

    on_exit(fn ->
      Application.delete_env(:triage, :app)
      Application.delete_env(:triage, :log_adapter)
    end)

    :ok
  end

  describe "validation" do
    test "mode must be :errors or :all" do
      assert_raise ArgumentError,
                   ~r/invalid value for :mode option: expected one of \[:errors, :all\], got: :something_else/,
                   fn ->
                     Triage.log(:ok, mode: :something_else)
                   end
    end
  end

  describe ".log with :error mode" do
    test "argument can only be a result" do
      assert_raise ArgumentError,
                   "Argument must be {:ok, ...} / :ok / {:error, ...} / :error, got: 123",
                   fn ->
                     123 |> Triage.log()
                   end
    end

    test "logs and passes through :error atom" do
      log =
        capture_log([level: :error], fn ->
          result = :error |> Triage.log()
          assert result == :error
        end)

      assert log =~ ~r<\[RESULT\] test/triage/log_test\.exs:\d+: :error>
    end

    test "logs and passes through {:error, binary}" do
      log =
        capture_log([level: :error], fn ->
          result = {:error, "something went wrong"} |> Triage.log()
          assert result == {:error, "something went wrong"}
        end)

      assert log =~
               ~r<\[RESULT\] test/triage/log_test\.exs:\d+: {:error, \"something went wrong\"}>
    end

    test "logs and passes through {:error, atom}" do
      log =
        capture_log([level: :error], fn ->
          result = {:error, :timeout} |> Triage.log()
          assert result == {:error, :timeout}
        end)

      assert log =~ ~r<\[RESULT\] test/triage/log_test\.exs:\d+: {:error, :timeout}>
    end

    test "logs and passes through {:error, atom, atom}" do
      log =
        capture_log([level: :error], fn ->
          result = {:error, :timeout, :very_cool} |> Triage.log()
          assert result == {:error, :timeout, :very_cool}
        end)

      assert log =~ ~r<\[RESULT\] test/triage/log_test\.exs:\d+: {:error, :timeout, :very_cool}>
    end

    test "logs and passes through {:error, exception}" do
      exception = %RuntimeError{message: "an example error message"}

      log =
        capture_log([level: :error], fn ->
          result = {:error, exception} |> Triage.log()
          assert result == {:error, exception}
        end)

      assert log =~
               ~r<\[RESULT\] test/triage/log_test\.exs:\d+: {:error, #RuntimeError\<\.\.\.\>} \(message: an example error message\)>
    end

    test "logs and passes through {:error, %Triage.WrappedError{}}" do
      exception =
        Triage.WrappedError.new({:error, :failed}, "fooing the bar", [
          # Made up stacktrace line using a real module so we get a realistic-ish line/number
          {Triage.TestHelper, :run_log, 2, [file: ~c"lib/triage/test_helper.ex", line: 10]}
        ])

      log =
        capture_log([level: :error], fn ->
          result = {:error, exception} |> Triage.log()
          assert result == {:error, exception}
        end)

      assert log =~
               ~r<\[RESULT\] test/triage/log_test\.exs:\d+: {:error, :failed}
    \[CONTEXT\] lib/triage/test_helper.ex:10: fooing the bar>
    end

    test "WrappedError with nil context" do
      exception =
        Triage.WrappedError.new(
          {:error, :failed},
          nil,
          [
            # Made up stacktrace line using a real module so we get a realistic-ish line/number
            {Triage.TestHelper, :run_log, 2, [file: ~c"lib/triage/test_helper.ex", line: 10]}
          ],
          %{foo: 123, bar: "baz"}
        )

      log =
        capture_log([level: :error], fn ->
          result = {:error, exception} |> Triage.log()
          assert result == {:error, exception}
        end)

      assert log =~
               ~r<\[RESULT\] test/triage/log_test\.exs:\d+: {:error, :failed}
    \[CONTEXT\] lib/triage/test_helper.ex:10: %{bar: \"baz\", foo: 123}>
    end

    test "WrappedError with raised exception" do
      func = fn i -> i * 2 end

      exception =
        Triage.WrappedError.new_raised(
          %RuntimeError{message: "an example error message"},
          # Raised exceptions get a func context when wrapped
          func,
          [
            # Made up stacktrace line using a real module so we get a realistic-ish line/number
            {Triage.TestHelper, :run_log, 2, [file: ~c"lib/triage/test_helper.ex", line: 10]}
          ]
        )

      log =
        capture_log([level: :error], fn ->
          result = {:error, exception} |> Triage.log()
          assert result == {:error, exception}
        end)

      assert log =~
               ~r<\[RESULT\] test/triage/log_test\.exs:\d+: \*\* \(RuntimeError\) an example error message
    \[CONTEXT\] lib/triage/test_helper.ex:10: Triage\.LogTest\.-test>
    end

    test "Nested WrappedError" do
      # Nested
      exception =
        Triage.WrappedError.new(
          {:error,
           Triage.WrappedError.new(
             {:error, %RuntimeError{message: "an example error message"}},
             "lower down",
             [
               {Triage.TestHelper, :made_up_function, 0,
                [file: ~c"lib/triage/test_helper.ex", line: 18]}
             ],
             %{a: 123, b: "baz"}
           )},
          "higher up",
          [
            {Triage.TestHelper, :run_log, 2, [file: ~c"lib/triage/test_helper.ex", line: 10]}
          ],
          %{b: "biz", something: %{whatever: :hello}, c: :foo}
        )

      log =
        capture_log([level: :error], fn ->
          result = {:error, exception} |> Triage.log()
          assert result == {:error, exception}
        end)

      assert log =~
               ~r<a=123 b=baz c=foo \[error\] \[RESULT\] test/triage/log_test\.exs:\d+: {:error, #RuntimeError\<\.\.\.\>} \(message: an example error message\)
    \[CONTEXT\] lib/triage/test_helper.ex:10: higher up %{b: "biz", c: :foo, something: %{whatever: :hello}}
    \[CONTEXT\] lib/triage/test_helper.ex:18: lower down %{a: 123, b: "baz"}>
    end

    test "does not log :ok atom" do
      log =
        capture_log([level: :error], fn ->
          result = :ok |> Triage.log()
          assert result == :ok
        end)

      assert log == ""
    end

    test "does not log {:ok, value}" do
      log =
        capture_log([level: :error], fn ->
          result = {:ok, "success"} |> Triage.log()
          assert result == {:ok, "success"}
        end)

      assert log == ""
    end
  end

  describe ".log with :all mode" do
    test "argument can only be a result" do
      assert_raise ArgumentError,
                   "Argument must be {:ok, ...} / :ok / {:error, ...} / :error, got: 123",
                   fn ->
                     123 |> Triage.log(mode: :all)
                   end
    end

    test "logs :error atom" do
      log =
        capture_log([level: :info], fn ->
          result = :error |> Triage.log(mode: :all)
          assert result == :error
        end)

      assert log =~ ~r<\[RESULT\] test/triage/log_test\.exs:\d+: :error>
    end

    test "logs {:error, binary}" do
      log =
        capture_log([level: :info], fn ->
          result = {:error, "something went wrong"} |> Triage.log(mode: :all)
          assert result == {:error, "something went wrong"}
        end)

      assert log =~
               ~r<\[RESULT\] test/triage/log_test\.exs:\d+: {:error, "something went wrong"}>
    end

    test "logs Ecto.Changeset error" do
      log =
        capture_log([level: :info], fn ->
          result =
            %User{}
            |> Ecto.Changeset.cast(%{name: 1}, [:name])
            |> Ecto.Changeset.apply_action(:insert)
            |> Triage.log(mode: :all)

          assert {:error,
                  %Ecto.Changeset{
                    valid?: false,
                    data: %Triage.LogTest.User{},
                    errors: [name: {"is invalid", [type: :string, validation: :cast]}]
                  }} = result
        end)

      # Uses Ecto's `inspect` implementation
      assert log =~
               ~r<\[RESULT\] test/triage/log_test\.exs:\d+: {:error, #Ecto\.Changeset\<action: :insert, changes: %{}, data: #Triage\.LogTest\.User\<id: nil, name: nil, \.\.\.\>, errors: \[name: {"is invalid", \[type: :string, validation: :cast\]}\], params: %{"name" =\> 1}, valid\?: false, \.\.\.\>}>
    end

    test "logs custom struct" do
      log =
        capture_log([level: :info], fn ->
          {:error, %CustomStruct{id: 123, foo: "thing", user_id: 456, bar: "other"}}
          |> Triage.log(mode: :all)
        end)

      # Uses Ecto's `inspect` implementation
      assert log =~
               ~r<\[RESULT\] lib\/ex_unit\/capture_log\.ex:\d+: {:error, #Triage\.LogTest\.CustomStruct\<id: 123, user_id: 456, \.\.\.\>}>
    end

    test "logs nested custom structs in error tuples" do
      log =
        capture_log([level: :error], fn ->
          {:error,
           %CustomStruct{
             id: 123,
             foo: "thing",
             user_id: 456,
             bar: %OtherCustomStruct{id: 789, name: "Cool", something: "hi", fooID: 000}
           }}
          |> Triage.log(mode: :all)
        end)

      # Uses Ecto's `inspect` implementation
      assert log =~
               ~r<\[RESULT\] lib\/ex_unit\/capture_log\.ex:\d+: {:error, #Triage\.LogTest\.CustomStruct\<id: 123, bar: #Triage.LogTest.OtherCustomStruct\<id: 789, name: \"Cool\", fooID: 0, \.\.\.\>, user_id: 456, \.\.\.\>}>
    end

    test "logs :ok atom" do
      log =
        capture_log([level: :info], fn ->
          result = :ok |> Triage.log(mode: :all)
          assert result == :ok
        end)

      assert log =~ ~r<\[RESULT\] test/triage/log_test\.exs:\d+: :ok>
    end

    test "logs {:ok, value}" do
      log =
        capture_log([level: :info], fn ->
          result = {:ok, "success"} |> Triage.log(mode: :all)
          assert result == {:ok, "success"}
        end)

      assert log =~ ~r<\[RESULT\] test/triage/log_test\.exs:\d+: {:ok, \"success\"}>
    end

    test "logs {:ok, value, value}" do
      log =
        capture_log([level: :info], fn ->
          result = {:ok, "success", :foo} |> Triage.log(mode: :all)
          assert result == {:ok, "success", :foo}
        end)

      assert log =~ ~r<\[RESULT\] test/triage/log_test\.exs:\d+: {:ok, \"success\", :foo}>
    end

    test "logs nested custom structs in ok tuples" do
      log =
        capture_log([level: :info], fn ->
          {:ok,
           %CustomStruct{
             id: 123,
             foo: "thing",
             user_id: 456,
             bar: %OtherCustomStruct{id: 789, name: "Cool", something: "hi", fooID: 000}
           }}
          |> Triage.log(mode: :all)
        end)

      # Uses Ecto's `inspect` implementation
      assert log =~
               ~r<\[RESULT\] lib\/ex_unit\/capture_log\.ex:\d+: {:ok, #Triage\.LogTest\.CustomStruct\<id: 123, bar: #Triage.LogTest.OtherCustomStruct\<id: 789, name: \"Cool\", fooID: 0, \.\.\.\>, user_id: 456, \.\.\.\>}>
    end
  end

  describe "Triage.log/2 log levels" do
    # :error results
    test "{:error, _} logs at level: :error - shows app line if app configured" do
      Application.put_env(:triage, :app, :triage)

      log =
        capture_log([level: :error], fn ->
          {:error, "test"} |> Triage.TestHelper.run_log(mode: :errors)
        end)

      assert log =~ ~r<\[RESULT\] lib/triage/test_helper\.ex:\d+: {:error, "test"}>

      # Should not appear at warning level
      log =
        capture_log([level: :critical], fn ->
          {:error, "test"} |> Triage.TestHelper.run_log(mode: :errors)
        end)

      refute log =~ ~r<RESULT>
    end

    test "{:error, _} logs at level: :error - shows best default line if app not configured " do
      log =
        capture_log([level: :error], fn ->
          {:error, "test"} |> Triage.log()
        end)

      # With no app configured, it defaults to the first level up
      assert log =~ ~r<\[RESULT\] lib/ex_unit/capture_log\.ex:\d+: {:error, "test"}>
    end

    test ":error logs at level: :error" do
      Application.put_env(:triage, :app, :triage)

      log =
        capture_log([level: :error], fn ->
          :error |> Triage.TestHelper.run_log(mode: :errors)
        end)

      assert log =~ ~r<\[RESULT\] lib/triage/test_helper\.ex:\d+: :error>

      # Should not appear at warning level
      log =
        capture_log([level: :critical], fn ->
          :error |> Triage.TestHelper.run_log(mode: :errors)
        end)

      refute log =~ "RESULT"
    end

    test "app configured, but :error result occurs where stacktrace does not have app" do
      Application.put_env(:triage, :app, :triage)

      log =
        capture_log([level: :error], fn ->
          :error |> Triage.log()
        end)

      assert log =~ ~r<\[RESULT\] :error>
    end

    # :ok results
    test "{:ok, _} logs at level: :info - shows app line if app configured" do
      Application.put_env(:triage, :app, :triage)

      log =
        capture_log([level: :info], fn ->
          {:ok, "test"} |> Triage.TestHelper.run_log(mode: :all)
        end)

      assert log =~ ~r<\[RESULT\] lib/triage/test_helper\.ex:9: {:ok, "test"}>

      # Should not appear at warning level
      log =
        capture_log([level: :notice], fn ->
          {:ok, "test"} |> Triage.TestHelper.run_log(mode: :all)
        end)

      refute log =~ ~r<RESULT>
    end

    test "{:ok, _} logs at level: :info - shows best default line if app not configured " do
      log =
        capture_log([level: :info], fn ->
          {:ok, "test"} |> Triage.log(mode: :all)
        end)

      # With no app configured, it defaults to the first level up
      assert log =~ ~r<\[RESULT\] lib/ex_unit/capture_log\.ex:\d+: {:ok, "test"}>
    end

    test ":ok logs at level: :info" do
      Application.put_env(:triage, :app, :triage)

      log =
        capture_log([level: :info], fn ->
          :ok |> Triage.TestHelper.run_log(mode: :all)
        end)

      assert log =~ ~r<\[RESULT\] lib/triage/test_helper\.ex:9: :ok>

      # Should not appear at warning level
      log =
        capture_log([level: :notice], fn ->
          :ok |> Triage.TestHelper.run_log(mode: :all)
        end)

      refute log =~ "RESULT"
    end

    test "app configured, but :ok result occurs where stacktrace does not have app" do
      Application.put_env(:triage, :app, :triage)

      log =
        capture_log([level: :info], fn ->
          :ok |> Triage.log(mode: :all)
        end)

      assert log =~ ~r<\[RESULT\] :ok>
    end

    test "no logs at any level if :ok result and mode is :errors" do
      log =
        capture_log([level: :debug], fn ->
          :ok |> Triage.log()
        end)

      refute log =~ "RESULT"

      log =
        capture_log([level: :debug], fn ->
          {:ok, 123} |> Triage.log()
        end)

      refute log =~ "RESULT"
    end
  end
end
