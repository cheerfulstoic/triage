defmodule Triage.JSONTest do
  use ExUnit.Case

  defmodule Person do
    defstruct [:id, :name, :age, :email, :role_id, :city, :country]
  end

  defmodule City do
    defstruct [:id, :population, :name, :year_founded]
  end

  defmodule CustomStruct do
    defstruct [:id, :foo, :user_id, :bar]
  end

  defmodule CustomError do
    defexception [:message, :code]
  end

  def shrink(value) do
    Triage.JSON.Shrink.shrink(value)
    |> tap(fn result ->
      # Shouldn't fail when encoding to JSON
      Jason.encode!(result)
    end)
  end

  describe "shrink/1 with basic values" do
    test "numbers pass through unchanged" do
      assert shrink(1) == 1
      assert shrink(963_256) == 963_256
      assert shrink(-1_235_358) == -1_235_358
      assert shrink(323.82354) == 323.82354
      assert shrink(-23.993523) == -23.993523
    end

    test "atoms pass through unchanged" do
      assert shrink(:atom) == :atom
      assert shrink(:foo) == :foo
      assert shrink(:bar) == :bar
      assert shrink(:some_atom) == :some_atom
      assert shrink(:CamelCase) == :CamelCase
      assert shrink(:"atom with spaces") == :"atom with spaces"
    end

    test "booleans and nil pass through unchanged" do
      assert shrink(true) == true
      assert shrink(false) == false
      assert shrink(nil) == nil
    end

    test "strings and binaries pass through unchanged" do
      assert shrink("") == ""
      assert shrink("hello") == "hello"
      assert shrink("hello world") == "hello world"
      assert shrink("string with\nnewlines") == "string with\nnewlines"
      assert shrink("string with\ttabs") == "string with\ttabs"
      assert shrink("string with \"quotes\"") == "string with \"quotes\""
      assert shrink("unicode: émojis 🎉 中文") == "unicode: émojis 🎉 中文"
      assert shrink(<<>>) == <<>>
      assert shrink(<<1, 2, 3>>) == <<1, 2, 3>>
      assert shrink(<<255, 254, 253>>) == "<<255, 254, 253>>"
    end
  end

  describe "shrink/1 with maps - filtering logic" do
    test "keeps id field" do
      assert shrink(%{id: 123, other: "value"}) == %{id: 123}
      assert shrink(%{"id" => 123, "other" => "value"}) == %{"id" => 123}
    end

    test "keeps name field" do
      assert shrink(%{name: "Alice", other: "value"}) == %{name: "Alice"}
      assert shrink(%{"name" => "Bob", "other" => "value"}) == %{"name" => "Bob"}
    end

    test "keeps both id and name fields" do
      assert shrink(%{id: 1, name: "Alice", age: 30}) == %{id: 1, name: "Alice"}
    end

    test "keeps fields matching *_id pattern" do
      assert shrink(%{user_id: 456, other: "value"}) == %{user_id: 456}
      assert shrink(%{role_id: 789, other: "value"}) == %{role_id: 789}
      assert shrink(%{account_id: 999, other: "value"}) == %{account_id: 999}
    end

    test "keeps fields matching *Id pattern (camelCase)" do
      assert shrink(%{userId: 456, other: "value"}) == %{userId: 456}
      assert shrink(%{roleId: 789, other: "value"}) == %{roleId: 789}
    end

    test "keeps fields matching *ID pattern (uppercase)" do
      assert shrink(%{userID: 456, other: "value"}) == %{userID: 456}
      assert shrink(%{roleID: 789, other: "value"}) == %{roleID: 789}
    end

    test "filters out fields with non-empty map values if the map doesn't have identifying fields" do
      nested = %{foo: "bar"}
      # The nested map shrinks to empty, which is not valuable as a sub-value
      assert shrink(%{data: nested, other: "value"}) == %{}
    end

    test "filters out fields with empty map values" do
      assert shrink(%{data: %{}, other: "value"}) == %{}
    end

    test "keeps fields with lists" do
      assert shrink(%{items: [1, 2, 3], other: "value"}) == %{items: [1, 2, 3]}
    end

    test "keeps fields with empty list values" do
      # Empty lists are still kept as they match the list filter criterion
      assert shrink(%{items: [], other: "value"}) == %{items: []}
    end

    test "filters out regular non-identifying fields" do
      result = shrink(%{age: 30, email: "test@example.com", address: "123 Main St"})
      assert result == %{}
    end

    test "complex map with multiple field types" do
      input = %{
        id: 1,
        name: "Alice",
        age: 30,
        user_id: 456,
        email: "alice@example.com",
        roles: [:admin, :user],
        metadata: %{foo: "bar"}
      }

      result = shrink(input)

      # roles list gets filtered out (simple values), metadata gets filtered out (empty after shrink)
      assert result == %{
               id: 1,
               name: "Alice",
               user_id: 456,
               roles: [:admin, :user]
             }
    end

    test "map with PID keys" do
      input = %{
        self() => 123
      }

      result = shrink(input)

      assert result == %{}
    end
  end

  describe "shrink/1 with nested maps" do
    test "recursively shrinks nested maps" do
      input = %{
        id: 1,
        name: "Alice",
        user: %{
          id: 2,
          name: "Bob",
          age: 25,
          email: "bob@example.com"
        }
      }

      result = shrink(input)

      assert result == %{
               id: 1,
               name: "Alice",
               user: %{id: 2, name: "Bob"}
             }
    end

    test "deeply nested maps" do
      input = %{
        id: 1,
        data: %{
          user_id: 2,
          profile: %{
            name: "Alice",
            age: 30,
            settings: %{
              theme: "dark",
              notifications: true
            }
          }
        }
      }

      result = shrink(input)

      # settings map has no identifying fields, so it shrinks to empty and gets filtered out
      assert result == %{
               id: 1,
               data: %{
                 user_id: 2,
                 profile: %{name: "Alice"}
               }
             }
    end
  end

  describe "shrink/1 with structs" do
    test "shrinks struct to identifying fields with __struct__ key" do
      person = %Person{
        id: 1,
        name: "Alice Johnson",
        age: 30,
        email: "alice@example.com",
        role_id: 5,
        city: "San Francisco",
        country: "USA"
      }

      result = shrink(person)

      assert result == %{
               __struct__: "Triage.JSONTest.Person",
               id: 1,
               name: "Alice Johnson",
               role_id: 5
             }
    end

    test "shrinks struct with nil values" do
      person = %Person{id: 2, name: "Bob"}

      result = shrink(person)

      assert result == %{
               __struct__: "Triage.JSONTest.Person",
               id: 2,
               name: "Bob",
               role_id: nil
             }
    end

    test "empty struct returns empty map when no identifying fields" do
      city = %City{}

      result = shrink(city)

      # All fields are nil and not identifying except id and name which are nil
      assert result == %{
               __struct__: "Triage.JSONTest.City",
               id: nil,
               name: nil
             }
    end

    test "nested structs are recursively shrunk" do
      person = %Person{
        id: 1,
        name: "Alice Johnson",
        age: 30,
        email: "alice@example.com",
        role_id: 5,
        city: %City{
          id: 2,
          population: 1_000_000,
          name: "Alicetown",
          year_founded: 2025
        },
        country: "USA"
      }

      result = shrink(person)

      assert result == %{
               __struct__: "Triage.JSONTest.Person",
               id: 1,
               name: "Alice Johnson",
               city: %{
                 __struct__: "Triage.JSONTest.City",
                 id: 2,
                 name: "Alicetown"
               },
               role_id: 5
             }
    end
  end

  describe "shrink/1 with exceptions" do
    test "shrinks standard exception" do
      exception = %RuntimeError{message: "an example error message"}

      result = shrink(exception)

      assert result == %{
               __struct__: "RuntimeError",
               __message__: "an example error message"
             }
    end

    test "shrinks ArgumentError" do
      exception = %ArgumentError{message: "bad argument"}

      result = shrink(exception)

      assert result == %{
               __struct__: "ArgumentError",
               __message__: "bad argument"
             }
    end

    test "shrinks custom exception with extra fields" do
      exception = %CustomError{message: "custom error", code: 500}

      result = shrink(exception)

      assert result == %{
               __struct__: "Triage.JSONTest.CustomError",
               __message__: "custom error",
               code: 500
             }
    end

    test "exception with nil message" do
      exception = %RuntimeError{message: nil}

      result = shrink(exception)

      # Exception.message/1 handles nil message with an error message
      assert result.__struct__ == "RuntimeError"
      assert result.__message__ =~ "got nil while retrieving Exception.message"
    end
  end

  describe "shrink/1 with WrappedError" do
    test "shrinks single WrappedError" do
      exception =
        Triage.WrappedError.new(
          {:error, :failed},
          "doing something",
          [{Triage.JSONTest, :test_function, 2, [file: ~c"test/shrink_test.exs", line: 10]}],
          %{foo: 123, bar: "baz"}
        )

      assert %{
               __root_reason__: :failed,
               __contexts__: [context]
             } = shrink(exception)

      assert context.label == "doing something"
      # Metadata gets shrunk - no identifying fields
      assert context.metadata == %{}
      assert context.stacktrace == ["test/shrink_test.exs:10: Triage.JSONTest.test_function/2"]
    end

    test "shrinks nested WrappedError" do
      nested_exception =
        Triage.WrappedError.new(
          {:error, %RuntimeError{message: "an example error message"}},
          "lower down",
          [{Triage.JSONTest, :made_up_function, 0, [file: ~c"test/shrink_test.exs", line: 18]}],
          %{foo: 123, bar: "baz"}
        )

      exception =
        Triage.WrappedError.new(
          {:error, nested_exception},
          "higher up",
          [{Triage.JSONTest, :test_function, 2, [file: ~c"test/shrink_test.exs", line: 10]}],
          %{something: %{whatever: :hello}}
        )

      assert %{
               __root_reason__: root_reason,
               __contexts__: [context1, context2]
             } = shrink(exception)

      assert root_reason == %{
               __struct__: "RuntimeError",
               __message__: "an example error message"
             }

      assert context1.label == "higher up"
      # Metadata gets shrunk - no identifying fields
      assert context1.metadata == %{}

      assert context2.label == "lower down"
      # Metadata gets shrunk - no identifying fields
      assert context2.metadata == %{}
    end

    test "WrappedError with nil context" do
      exception =
        Triage.WrappedError.new(
          {:error, :failed},
          nil,
          [{Triage.JSONTest, :test_function, 2, [file: ~c"test/shrink_test.exs", line: 10]}],
          %{foo: 123}
        )

      assert %{
               __root_reason__: :failed,
               __contexts__: [context]
             } = shrink(exception)

      assert context.label == nil
      # Metadata gets shrunk - no identifying fields
      assert context.metadata == %{}
    end
  end

  describe "shrink/1 with lists" do
    test "empty list returns empty list" do
      assert shrink([]) == []
    end

    test "keyword list is converted to map and shrunk" do
      result = shrink(id: 1, name: "Alice", age: 30)
      assert result == %{id: 1, name: "Alice"}
    end

    test "list of simple values" do
      assert shrink([1, 2, 3]) == [1, 2, 3]
    end

    test "list of maps is recursively shrunk" do
      input = [
        %{id: 1, name: "Alice", age: 30},
        %{id: 2, name: "Bob", age: 25}
      ]

      assert shrink(input) == [
               %{id: 1, name: "Alice"},
               %{id: 2, name: "Bob"}
             ]
    end

    test "nested lists are recursively shrunk" do
      input = [
        [%{id: 1, name: "Alice"}],
        [%{id: 2, name: "Bob"}]
      ]

      # Each sub-list contains valuable items
      assert shrink(input) == [
               [%{id: 1, name: "Alice"}],
               [%{id: 2, name: "Bob"}]
             ]
    end
  end

  describe "shrink/1 with tuples" do
    test "empty tuple is converted to string" do
      assert shrink({}) == "{}"
    end

    test "single element tuple is converted to string" do
      assert shrink({1}) == "{1}"
    end

    test "two element tuple is converted to string" do
      assert shrink({1, 2}) == "{1, 2}"
    end

    test "ok tuple is converted to string" do
      assert shrink({:ok, "success"}) == "{:ok, \"success\"}"
    end

    test "error tuple is converted to string" do
      assert shrink({:error, :not_found}) == "{:error, :not_found}"
    end

    test "nested tuple is converted to string" do
      assert shrink({{1, 2}, {3, 4}}) == "{{1, 2}, {3, 4}}"
    end
  end

  describe "shrink/1 with functions" do
    test "anonymous function is converted to Module.name/arity format" do
      func = fn x -> x + 1 end

      assert shrink(func) =~ ~r/^&Triage\.JSONTest\.\-test shrink\/1.*\/1/
    end

    test "captured function is converted to Module.name/arity format" do
      func = &String.upcase/1

      assert shrink(func) == "&String.upcase/1"
    end

    test "function with multiple arities" do
      func = &Enum.map/2
      result = shrink(func)

      assert result == "&Enum.map/2"
    end
  end

  describe "edge cases" do
    test "map with tuple values" do
      input = %{id: 1, coords: {10, 20}}

      result = shrink(input)

      # Tuple values get converted to strings, but coords is not an identifying field
      # so it gets filtered out
      assert result == %{id: 1}
    end

    test "map with function values" do
      func = &String.upcase/1
      input = %{id: 1, transformer: func}

      result = shrink(input)

      # Function values get converted to strings, but transformer is not an identifying field
      # so it gets filtered out
      assert result == %{id: 1}
    end

    test "struct with list field" do
      custom = %CustomStruct{
        id: 1,
        foo: "bar",
        user_id: 456,
        bar: [1, 2, 3]
      }

      assert shrink(custom) == %{
               __struct__: "Triage.JSONTest.CustomStruct",
               id: 1,
               user_id: 456,
               bar: [1, 2, 3]
             }
    end

    test "struct with map field" do
      custom = %CustomStruct{
        id: 1,
        foo: "bar",
        user_id: 456,
        bar: %{name: "test", age: 30}
      }

      result = shrink(custom)

      assert result == %{
               __struct__: "Triage.JSONTest.CustomStruct",
               id: 1,
               user_id: 456,
               bar: %{name: "test"}
             }
    end

    test "list with mix of valuable and non-valuable items" do
      input = [
        %{id: 1, name: "Alice"},
        %{age: 30}
      ]

      result = shrink(input)

      # First item has valuable data after shrinking, second doesn't
      assert result == [
               %{id: 1, name: "Alice"},
               %{}
             ]
    end
  end
end
