defmodule Triage.UserMessageTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  test "Just passes strings through" do
    assert Triage.user_message({:error, "There was a really weird error"}) ==
             "There was a really weird error"
  end

  test "Atom" do
    {result, log} =
      with_log([level: :error], fn -> Triage.user_message({:error, :some_error_atom}) end)

    assert result =~ ~r/There was an error\. Refer to code: [A-Z0-9]{8}/
    [_, code] = Regex.run(~r/Refer to code: ([A-Z0-9]{8})/, result)
    assert log =~ ~r/#{code}: Could not generate user error message. Error was: :some_error_atom/
  end

  test "Exception" do
    {result, log} =
      with_log(fn ->
        Triage.user_message({:error, %RuntimeError{message: "an example error message"}})
      end)

    assert result =~
             ~r/There was an error\. Refer to code: [A-Z0-9]{8}/

    [_, code] = Regex.run(~r/Refer to code: ([A-Z0-9]{8})/, result)

    assert log =~
             ~r/#{code}: Could not generate user error message. Error was: #RuntimeError<\.\.\.> \(message: an example error message\)/
  end

  test "WrappedError - originally string" do
    exception =
      Triage.WrappedError.new({:error, "The original message"}, "fooing the bar", [
        # Made up stacktrace line using a real module so we get a realistic-ish line/number
        {Triage.TestHelper, :run_log, 2, [file: ~c"lib/errors/test_helper.ex", line: 10]}
      ])

    assert Triage.user_message({:error, exception}) ==
             "The original message (happened while: fooing the bar)"

    exception =
      Triage.WrappedError.new(
        {:error,
         Triage.WrappedError.new(
           {:error, "The original message"},
           "lower down",
           [
             {Triage.TestHelper, :made_up_function, 0,
              [file: ~c"lib/errors/test_helper.ex", line: 18]}
           ],
           %{foo: 123, bar: "baz"}
         )},
        "higher up",
        [
          {Triage.TestHelper, :run_log, 2, [file: ~c"lib/errors/test_helper.ex", line: 10]}
        ],
        %{something: %{whatever: :hello}}
      )

    assert Triage.user_message({:error, exception}) ==
             "The original message (happened while: higher up => lower down)"
  end

  test "WrappedError - originally atom" do
    exception =
      Triage.WrappedError.new({:error, :some_original_error}, "fooing the bar", [
        # Made up stacktrace line using a real module so we get a realistic-ish line/number
        {Triage.TestHelper, :run_log, 2, [file: ~c"lib/errors/test_helper.ex", line: 10]}
      ])

    {result, log} = with_log(fn -> Triage.user_message({:error, exception}) end)

    assert result =~
             ~r/There was an error\. Refer to code: [A-Z0-9]{8} \(happened while: fooing the bar\)/

    [_, code] = Regex.run(~r/Refer to code: ([A-Z0-9]{8})/, result)

    assert log =~
             ~r/#{code}: Could not generate user error message. Error was: :some_original_error/

    exception =
      Triage.WrappedError.new(
        {:error,
         Triage.WrappedError.new(
           {:error, :some_original_error},
           "lower down",
           [
             {Triage.TestHelper, :made_up_function, 0,
              [file: ~c"lib/errors/test_helper.ex", line: 18]}
           ],
           %{foo: 123, bar: "baz"}
         )},
        "higher up",
        [
          {Triage.TestHelper, :run_log, 2, [file: ~c"lib/errors/test_helper.ex", line: 10]}
        ],
        %{something: %{whatever: :hello}}
      )

    {result, log} = with_log(fn -> Triage.user_message({:error, exception}) end)

    assert result =~
             ~r/There was an error\. Refer to code: [A-Z0-9]{8} \(happened while: higher up => lower down\)/

    [_, code] = Regex.run(~r/Refer to code: ([A-Z0-9]{8})/, result)

    assert log =~
             ~r/#{code}: Could not generate user error message. Error was: :some_original_error/
  end

  test "WrappedError - originally exception" do
    exception =
      Triage.WrappedError.new(
        {:error, %RuntimeError{message: "an example error message"}},
        "fooing the bar",
        [
          # Made up stacktrace line using a real module so we get a realistic-ish line/number
          {Triage.TestHelper, :run_log, 2, [file: ~c"lib/errors/test_helper.ex", line: 10]}
        ]
      )

    {result, log} = with_log(fn -> Triage.user_message({:error, exception}) end)

    assert result =~
             ~r/There was an error\. Refer to code: [A-Z0-9]{8} \(happened while: fooing the bar\)/

    [_, code] = Regex.run(~r/Refer to code: ([A-Z0-9]{8})/, result)

    assert log =~
             ~r/#{code}: Could not generate user error message. Error was: #RuntimeError<\.\.\.> \(message: an example error message\)/
  end

  test "WrappedError - originally :error" do
    exception =
      Triage.WrappedError.new(
        {:error, :error},
        "fooing the bar",
        [
          # Made up stacktrace line using a real module so we get a realistic-ish line/number
          {Triage.TestHelper, :run_log, 2, [file: ~c"lib/errors/test_helper.ex", line: 10]}
        ]
      )

    {result, log} = with_log(fn -> Triage.user_message({:error, exception}) end)

    assert result =~
             ~r/There was an error\. Refer to code: [A-Z0-9]{8} \(happened while: fooing the bar\)/

    [_, code] = Regex.run(~r/Refer to code: ([A-Z0-9]{8})/, result)

    assert log =~
             ~r/#{code}: Could not generate user error message. Error was: :error/
  end

  describe "Ecto.Changeset" do
    test "single field with single error" do
      changeset =
        {%{}, %{email: :string}}
        |> Ecto.Changeset.cast(%{}, [:email])
        |> Ecto.Changeset.validate_required([:email])

      assert Triage.user_message({:error, changeset}) == "email: can't be blank"
    end

    test "single field with multiple errors" do
      changeset =
        {%{}, %{email: :string}}
        |> Ecto.Changeset.cast(%{email: "invalid"}, [:email])
        |> Ecto.Changeset.validate_required([:email])
        |> Ecto.Changeset.validate_format(:email, ~r/@/)
        |> Ecto.Changeset.validate_length(:email, min: 10)

      assert Triage.user_message({:error, changeset}) ==
               "email: has invalid format, should be at least 10 character(s)"
    end

    test "multiple fields with errors" do
      changeset =
        {%{}, %{email: :string, age: :integer, name: :string}}
        |> Ecto.Changeset.cast(%{age: 15}, [:email, :age, :name])
        |> Ecto.Changeset.validate_required([:email, :name])
        |> Ecto.Changeset.validate_number(:age, greater_than: 18)

      assert Triage.user_message({:error, changeset}) ==
               "age: must be greater than 18; email: can't be blank; name: can't be blank"
    end

    test "error with interpolated values" do
      changeset =
        {%{}, %{password: :string}}
        |> Ecto.Changeset.cast(%{password: "short"}, [:password])
        |> Ecto.Changeset.validate_length(:password, min: 8)

      assert Triage.user_message({:error, changeset}) ==
               "password: should be at least 8 character(s)"
    end

    test "base errors without field prefix" do
      changeset =
        {%{}, %{email: :string}}
        |> Ecto.Changeset.cast(%{email: "test@example.com"}, [:email])
        |> Ecto.Changeset.add_error(:base, "either email or username must be unique")

      assert Triage.user_message({:error, changeset}) ==
               "either email or username must be unique"
    end

    # Honestly I don't know if this is a thing or if it even should be a thing
    # but `nil` is an atom, so it *can* be a thing, so we might as well support it
    # properly if anybody ever does it (and because I did it in an app 😉)
    test "nil field errors without field prefix" do
      changeset =
        {%{}, %{email: :string}}
        |> Ecto.Changeset.cast(%{email: "test@example.com"}, [:email])
        |> Ecto.Changeset.add_error(nil, "either email or username must be unique")

      assert Triage.user_message({:error, changeset}) ==
               "either email or username must be unique"
    end

    test "empty changeset with no errors" do
      changeset =
        {%{}, %{email: :string}}
        |> Ecto.Changeset.cast(%{email: "valid@example.com"}, [:email])

      # Edge case: valid changeset passed as error
      assert Triage.user_message({:error, changeset}) == ""
    end

    test "mix of base and field errors" do
      changeset =
        {%{}, %{email: :string, username: :string}}
        |> Ecto.Changeset.cast(%{}, [:email, :username])
        |> Ecto.Changeset.validate_required([:email])
        |> Ecto.Changeset.add_error(:base, "either email or username required")

      result = Triage.user_message({:error, changeset})

      # Base errors come first alphabetically, then field errors
      assert result == "either email or username required; email: can't be blank"
    end

    test "multiple base errors" do
      changeset =
        {%{}, %{}}
        |> Ecto.Changeset.cast(%{}, [])
        |> Ecto.Changeset.add_error(:base, "first base error")
        |> Ecto.Changeset.add_error(:base, "second base error")

      assert Triage.user_message({:error, changeset}) ==
               "first base error, second base error"
    end

    test "validate_format for email" do
      changeset =
        {%{}, %{email: :string}}
        |> Ecto.Changeset.cast(%{email: "notanemail"}, [:email])
        |> Ecto.Changeset.validate_format(:email, ~r/@/)

      assert Triage.user_message({:error, changeset}) == "email: has invalid format"
    end

    test "validate_format for email - custom message" do
      changeset =
        {%{}, %{email: :string}}
        |> Ecto.Changeset.cast(%{email: "notanemail"}, [:email])
        |> Ecto.Changeset.validate_format(:email, ~r/@/, message: "custom message")

      assert Triage.user_message({:error, changeset}) == "email: custom message"
    end

    test "validate_subset with list" do
      changeset =
        {%{}, %{tags: {:array, :string}}}
        |> Ecto.Changeset.cast(%{tags: ["elixir", "invalid", "phoenix"]}, [:tags])
        |> Ecto.Changeset.validate_subset(:tags, ["elixir", "phoenix", "erlang"])

      assert Triage.user_message({:error, changeset}) ==
               ~s(tags: expected to be a subset of ["elixir", "phoenix", "erlang"])
    end

    test "validate_subset with range" do
      changeset =
        {%{}, %{numbers: {:array, :integer}}}
        |> Ecto.Changeset.cast(%{numbers: [1, 5, 10]}, [:numbers])
        |> Ecto.Changeset.validate_subset(:numbers, 1..8)

      assert Triage.user_message({:error, changeset}) ==
               "numbers: expected to be a subset of 1..8"
    end

    test "validate_change with custom validation" do
      changeset =
        {%{}, %{username: :string}}
        |> Ecto.Changeset.cast(%{username: "admin"}, [:username])
        |> Ecto.Changeset.validate_change(:username, fn :username, value ->
          if value == "admin", do: [username: "reserved username"], else: []
        end)

      assert Triage.user_message({:error, changeset}) == "username: reserved username"
    end

    test "validate_inclusion" do
      changeset =
        {%{}, %{role: :string}}
        |> Ecto.Changeset.cast(%{role: "superadmin"}, [:role])
        |> Ecto.Changeset.validate_inclusion(:role, ["user", "admin", "moderator"])

      assert Triage.user_message({:error, changeset}) ==
               ~s(role: must be one of: ["user", "admin", "moderator"])
    end

    test "validate_exclusion" do
      changeset =
        {%{}, %{username: :string}}
        |> Ecto.Changeset.cast(%{username: "admin"}, [:username])
        |> Ecto.Changeset.validate_exclusion(:username, ["admin", "root", "system"])

      assert Triage.user_message({:error, changeset}) ==
               ~s(username: cannot be one of: ["admin", "root", "system"])
    end

    test "validate_number with greater_than" do
      changeset =
        {%{}, %{age: :integer}}
        |> Ecto.Changeset.cast(%{age: 15}, [:age])
        |> Ecto.Changeset.validate_number(:age, greater_than: 18)

      assert Triage.user_message({:error, changeset}) == "age: must be greater than 18"
    end

    test "validate_number with less_than_or_equal_to" do
      changeset =
        {%{}, %{score: :integer}}
        |> Ecto.Changeset.cast(%{score: 150}, [:score])
        |> Ecto.Changeset.validate_number(:score, less_than_or_equal_to: 100)

      assert Triage.user_message({:error, changeset}) ==
               "score: must be less than or equal to 100"
    end

    test "validate_number with equal_to" do
      changeset =
        {%{}, %{quantity: :integer}}
        |> Ecto.Changeset.cast(%{quantity: 5}, [:quantity])
        |> Ecto.Changeset.validate_number(:quantity, equal_to: 10)

      assert Triage.user_message({:error, changeset}) == "quantity: must be equal to 10"
    end
  end
end
