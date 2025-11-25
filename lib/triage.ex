defmodule Triage do
  @moduledoc """
  Documentation for `Triage`.
  """

  alias Triage.Results
  alias Triage.Stacktrace
  alias Triage.WrappedError
  alias Triage.Validate
  require Logger
  require Stacktrace

  @type result() :: :ok | {:ok, any()} | :error | {:error, any()}
  @type value_result() :: {:ok, any()} | :error | {:error, any()}

  @doc group: "Functions > Contexts"
  @doc """
  Wraps `t:result/0` with additional context information, leaving `:ok` results unchanged.

  Takes a result tuple and wraps error cases (`:error` or `{:error, reason}`) with
  a context string, metadata, and stacktrace info contained in `Triage.WrappedError{}`.

  If the second argument is a string, the context is set. If the second argument is a
  keyword list or a map the metadata is set.  The arity 3 version allows setting both.

  Because the context is designed to show what was happening in logs or in user error
  messages, the context string should describe what is being attempted in **business logic**
  terms. e.g.:

   * GOOD: "connecting to user service" (describe the action)
   * BAD: "failed to connect to user service" ("failed to connect" describes a failure)
   * BAD: "HTTP request to user_authentication server" (technical terms)

  The `log/2` and `user_message/1` functions support `WrappedError` results. See their
  docs for more details

  ## Examples

      iex> Triage.wrap_context(:ok, "fetching user")
      :ok

      iex> Triage.wrap_context({:ok, 42}, "fetching user")
      {:ok, 42}

      iex> Triage.wrap_context(:error, "fetching user")
      {:error, %Triage.WrappedError{}}

      iex> Triage.wrap_context({:error, :not_found}, "fetching user", %{user_id: 123})
      {:error, %Triage.WrappedError{}}

      iex> Triage.wrap_context({:error, :not_found}, %{user_id: 123})
      {:error, %Triage.WrappedError{}}
  """
  @spec wrap_context(result(), String.t() | keyword() | map()) ::
          :ok | {:ok, any()} | {:error, Triage.WrappedError.t()}

  def wrap_context(result, context) when is_binary(context) do
    wrap_context(result, context, %{})
  end

  def wrap_context(result, metadata) when is_map(metadata) or is_list(metadata) do
    wrap_context(result, nil, metadata)
  end

  @doc group: "Functions > Contexts"
  @doc """
  Wrap errors from a result with both a context string and metadata. See `wrap_context/2`
  """
  @spec wrap_context(result(), String.t() | nil, keyword() | map()) ::
          :ok | {:ok, any()} | {:error, Triage.WrappedError.t()}

  # def wrap_context(result, context, meta \\ %{})

  def wrap_context(:ok, _context, _meta), do: :ok

  def wrap_context(result, _, _) when is_tuple(result) and elem(result, 0) == :ok do
    result
  end

  def wrap_context(:error, context, metadata) do
    stacktrace = Stacktrace.calling_stacktrace()

    {:error, WrappedError.new(:error, context, stacktrace, metadata)}
  end

  def wrap_context(result, context, metadata)
      when is_tuple(result) and elem(result, 0) == :error do
    stacktrace = Stacktrace.calling_stacktrace()

    {:error, WrappedError.new(result, context, stacktrace, metadata)}
  end

  @doc group: "Functions > Control Flow"
  @doc """
  Executes a function that returns a result tuple, without exception handling.

  Calls the provided zero-arity function and checks that it returns a result
  (`:ok`, `{:ok, value}`, `:error`, or `{:error, reason}`). If the function returns
  any other value, it wraps it in `{:ok, value}`.

  This is the "unsafe" version that doesn't catch exceptions. Use `run/1` for
  exception handling.

  ## Parameters

    * `func` - A zero-arity function that returns a result

  ## Examples

      iex> run!(fn -> 42 end)
      {:ok, 42}

      iex> run!(fn -> {:ok, 42} end)
      {:ok, 42}

      iex> run!(fn -> {:error, :not_found} end)
      {:error, :not_found}

      iex> run!(fn -> :error end)
      :error

      iex> run!(&function_to_try, retries: 2)
      :error
  """
  @spec run!((-> any())) :: result()
  @spec run!((-> any()), retries: non_neg_integer()) :: result()
  def run!(func, opts \\ []) do
    opts = validate_run_opts!(opts)

    ok_then!(
      {:ok, nil},
      fn _ -> func.() end,
      opts
    )
  end

  @doc group: "Functions > Control Flow"
  @doc """
  Executes a function that returns a result tuple, with exception handling.

  Calls the provided zero-arity function and ensures it returns a valid result.
  If the function raises an exception, it catches it and returns
  `{:error, %Triage.WrappedError{}}` with details about the exception.

  ## Parameters

    * `func` - A zero-arity function that returns a result

  ## Examples

      iex> run(fn -> {:ok, 42} end)
      {:ok, 42}

      iex> run(fn -> raise "boom" end)
      {:error, %Triage.WrappedError{}}
  """
  @spec run((-> any())) :: result()
  @spec run((-> any()), retries: non_neg_integer()) :: result()
  def run(func, opts \\ []) do
    opts = validate_run_opts!(opts)

    try do
      run!(func, opts)
    rescue
      exception ->
        if opts[:retries] == 0 do
          {:error, WrappedError.new_raised(exception, func, __STACKTRACE__)}
        else
          run(func, Keyword.update!(opts, :retries, &(&1 - 1)))
        end
    end
  end

  defp validate_run_opts!(opts) do
    # Same logic (for now)
    validate_ok_then_opts!(opts)
  end

  @doc group: "Functions > Control Flow"
  @doc """
  Executes a function with a previous result value, without exception handling.

  Takes a result and, if it's an :ok, passes the value from the tuple to the provided function.
  If the result was an error, short-circuits and returns the error without calling the function.

  This is the "unsafe" version that doesn't catch exceptions. Use `ok_then/2` for
  exception handling.

  ## Parameters

    * `result` - The previous result (`:ok`, `{:ok, value}`, `:error`, or `{:error, reason}`)
    * `func` - A function that takes the unwrapped value and returns a result

  ## Examples

      iex> ok_then!({:ok, 5}, fn x -> {:ok, x * 2} end)
      {:ok, 10}

      iex> ok_then!({:error, :not_found}, fn x -> {:ok, x * 2} end)
      {:error, :not_found}
  """
  @spec ok_then!(result(), (any() -> any())) :: result()
  @spec ok_then!(result(), (any() -> any()), retries: non_neg_integer()) :: result()
  def ok_then!(result, func, opts \\ [])

  def ok_then!(:ok, func, opts) do
    ok_then!({:ok, nil}, func, opts)
  end

  def ok_then!({:ok, value}, func, opts) do
    opts = validate_ok_then_opts!(opts)

    result = func.(value)

    case result_type(result) do
      :ok ->
        result

      :error ->
        if opts[:retries] == 0 do
          result
        else
          ok_then!({:ok, value}, func, Keyword.update!(opts, :retries, &(&1 - 1)))
        end

      _ ->
        {:ok, result}
    end
  end

  def ok_then!(:error, _func, _opts), do: :error

  def ok_then!({:error, _} = result, _func, _opts), do: result
  def ok_then!(other, _, _), do: Validate.validate_result!(other, :strict)

  @doc group: "Functions > Control Flow"
  @doc """
  Executes a function with a previous result value, with exception handling.

  Takes a result and, if :ok, passes the value from the tuple to the provided function.
  If the previous result was an error, short-circuits and returns the error.

  If the function raises an exception, it catches it and returns
  `{:error, %Triage.WrappedError{}}` with details about the exception.

  ## Parameters

    * `result` - The previous result (`:ok`, `{:ok, value}`, `:error`, or `{:error, reason}`)
    * `func` - A function that takes the unwrapped value and returns a result

  ## Examples

      iex> ok_then({:ok, 5}, fn x -> {:ok, x * 2} end)
      {:ok, 10}

      iex> ok_then({:ok, 5}, fn _x -> raise "boom" end)
      {:error, %Triage.WrappedError{}}
  """
  @spec ok_then(result(), (any() -> any())) :: result()
  @spec ok_then(result(), (any() -> any()), retries: non_neg_integer()) :: result()
  def ok_then(result, func, opts \\ [])

  def ok_then(result, func, opts) do
    opts = validate_ok_then_opts!(opts)

    try do
      ok_then!(result, func, opts)
    rescue
      exception ->
        if opts[:retries] == 0 do
          {:error, WrappedError.new_raised(exception, func, __STACKTRACE__)}
        else
          ok_then(result, func, Keyword.update!(opts, :retries, &(&1 - 1)))
        end
    end
  end

  defp validate_ok_then_opts!(opts) do
    NimbleOptions.validate(opts,
      retries: [
        type: :non_neg_integer,
        default: 0
      ]
    )
    |> case do
      {:error, %NimbleOptions.ValidationError{} = error} ->
        raise ArgumentError, Exception.message(error)

      {:ok, opts} ->
        opts
    end
  end

  @doc group: "Functions > Control Flow"
  @doc """
  Executes a side-effect function when the result is :ok, passing the result through unchanged.

  Takes a result and, if it's `:ok` or `{:ok, value}`, calls the provided function with
  the unwrapped value (or `nil` for `:ok`). The result is always returned unchanged,
  making this useful for side effects like logging or debugging.

  If the result is an error, the function is not called and the error is returned unchanged.

  ## Examples

      # Track analytics for successful user registrations
      iex> register_user(params)
      ...> |> tap_ok(fn user -> Analytics.track("user_registered", %{user_id: user.id}) end)
      {:ok, %User{email: "user@example.com"}}

      # Cache API responses while continuing the pipeline
      iex> fetch_product_from_api(product_id)
      ...> |> tap_ok(fn product -> Cache.put("product:\#{product_id}", product) end)
      {:ok, %Product{id: 123, name: "Widget"}}

      # Errors pass through without calling the function
      iex> tap_ok({:error, :not_found}, fn user -> send_notification(user) end)
      {:error, :not_found}
  """
  @spec tap_ok(result(), (any() -> any())) :: result()
  def tap_ok(result, func) do
    Validate.validate_result!(result, :strict)

    case result do
      :ok ->
        func.(nil)

      {:ok, value} ->
        func.(value)

      _ ->
        # Ignored
        nil
    end

    result
  end

  @doc group: "Functions > Control Flow"
  @doc """
  Executes a side-effect function when the result is an error, passing the result through unchanged.

  Takes a result and, if it's `:error` or `{:error, reason}`, calls the provided function
  with the unwrapped reason (or `nil` for `:error`). The result is always returned unchanged,
  making this useful for side effects like logging or debugging errors.

  If the result is :ok, the function is not called and the :ok result is returned unchanged.

  ## Examples

      # Monitor payment failures and send alerts
      iex> process_payment(order)
      ...> |> tap_error(fn reason ->
      ...>   ErrorTracker.report(reason, context: %{order_id: order.id})
      ...>   if reason == :payment_gateway_down, do: PagerDuty.alert("Gateway down")
      ...> end)
      {:error, :payment_gateway_down}

      # Track metrics for failed operations
      iex> update_inventory(product_id, quantity)
      ...> |> tap_error(fn reason ->
      ...>   ErrorTracker.report(reason, context: %{product_id: product_id})
      ...>   Metrics.increment("inventory.update.failed", tags: %{reason: reason})
      ...> end)
      {:error, :insufficient_stock}

      # Success results pass through without calling the function
      iex> tap_error({:ok, user}, fn _ -> ErrorTracker.report("Won't be called") end)
      {:ok, %User{}}
  """
  @spec tap_error(result(), (any() -> any())) :: result()
  def tap_error(result, func) do
    Validate.validate_result!(result, :strict)

    case result do
      :error ->
        func.(nil)

      {:error, reason} ->
        func.(reason)

      _ ->
        # Ignored
        nil
    end

    result
  end

  @doc group: "Functions > Control Flow"
  @doc """
  For dealing with `:error` cases, passing `:ok` results through unchanged.

  When given result is `{:error, reason}`, the `reason` is passed into the callback
  function. The callback function can then return a new `reason` which will be
  returned from `error_then` wrapped in an `{:error, _}` tuple.

  If `:error` is the given result, `nil` will be given to the callback function.

  The callback function can also return `:ok` or `{:ok, any()}` to have the error
  be ignored and the `:ok` result will be returned instead.

  ## Examples

      iex> ping_account_server() |> Triage.error_then(fn _ -> :account_server_failure end)
      {:error, :account_server_failure}

      iex> Triage.error_then({:error, :unknown}, fn :unknown -> {:ok, @default_value} end)
      {:ok, ...}

      iex> Triage.error_then(:ok, fn _ -> :not_used end)
      :ok

      iex> Triage.error_then({:ok, ...}, fn _ -> :not_used end)
      {:ok, 42}

      iex> Triage.error_then(:error, fn nil -> :handled end)
      {:error, :handled}
  """
  @spec error_then(result(), (any() -> any())) :: result()
  def error_then(:error, func), do: error_then({:error, nil}, func)

  def error_then({:error, reason}, func) do
    result = func.(reason)

    case result_type(result) do
      :ok ->
        result

      :error ->
        result

      nil ->
        if result == nil do
          :error
        else
          {:error, result}
        end
    end
  end

  def error_then(result, _) do
    Validate.validate_result!(result, :strict)

    result
  end

  @doc group: "Functions > Enumeration"
  @doc """
  Maps a function over an enumerable, collecting successful values and short-circuiting on the first error.

  Takes an enumerable or `{:ok, enumerable}` and applies a function to each element.
  If all callbacks return success with `{:ok, value}`), `map_if` returns
  `{:ok, [transformed_values]}`. If any call to the callback returns an error, `map_if`
  immediately stops processing and returns that error.

  If `map_if` is given an `:error` result for it's first argument that argument is returned
  unchanged and the callback is never called.

  Since `map_if` requires an enumerable value to work with, it will fail if given `:ok` as a result argument.

  This is useful when you need all transformations to succeed—if any fail, you don't want
  the partial results.

  ## Examples

      iex> Triage.map_if(xml_docs, & xml_to_json(&1, opts))
      {:ok, [...]}

      iex> Triage.map_if(xml_docs, & xml_to_json(&1, opts))
      {:error, ...}

      iex> Triage.map_if(:error, fn _ -> <not called> end)
      :error

      iex> Triage.map_if({:error, :not_found}, fn _ -> <not called end)
      {:error, :not_found}
  """
  @spec map_if(result(), (any() -> any())) :: result()
  def map_if({:ok, value}, func), do: map_if(value, func)
  def map_if(:error, _), do: :error
  def map_if({:error, _} = error, _), do: error

  def map_if(values, func) do
    {:ok,
     Enum.map(values, fn value ->
       case func.(value) do
         # :ok ->
         {:ok, value} ->
           value

         :error ->
           throw({:__ERRORS__, :error})

         {:error, _} = error ->
           throw({:__ERRORS__, error})
       end
     end)}
  catch
    {:__ERRORS__, result} ->
      result
  end

  @doc group: "Functions > Enumeration"
  @doc """
  Finds the first successful result from applying a function to enumerable elements.

  Takes an enumerable or `{:ok, enumerable}` and applies a function to each element
  The first successful result (`:ok` or `{:ok, value}`) from the callback is returned
  from `find_value` and no further iteration is done.

  If all callbacks return errors, then `{:error, [list of error reasons]}` is returned.
  For `:error` atoms in the error list, they are represented as `nil`.

  If `:error` or `{:error, reason}` is given as the first argument to `find_value`,
  it is passed through unchanged.

  This can be useful when you're trying multiple strategies or checking multiple
  values to find the first one that works.

  ## Examples

      iex> Triage.find_value(domains, &ping_domain)
      {:ok, "www.mydomain.com"}

      iex> Triage.find_value({:ok, domains}, &ping_domain)
      {:error, [:nxdomain, :timeout, :nxdomain]}

      iex> Triage.find_value(:error, fn _ -> <not called> end)
      :error

      iex> Triage.find_value({:error, :not_found}, fn _ -> <not called> end)
      {:error, :not_found}
  """
  @spec find_value(value_result() | Enumerable.t(), (any() -> result())) ::
          :ok | {:ok, any()} | {:error, [any()]}
  def find_value({:ok, input}, func), do: find_value(input, func)
  def find_value(:error, _), do: :error
  def find_value({:error, _} = error, _), do: error

  def find_value(input, func) do
    errors =
      Enum.map(input, fn value ->
        case func.(value) do
          :ok ->
            throw({:__ERRORS__, :ok})

          {:ok, _} = result ->
            throw({:__ERRORS__, result})

          :error ->
            nil

          {:error, reason} ->
            reason

          other ->
            Validate.validate_result!(other, :strict, "Callback return")
        end
      end)

    {:error, errors}
  catch
    {:__ERRORS__, result} ->
      result
  end

  @doc group: "Functions > Enumeration"
  @doc """
  Validates that a callback function gives an `:ok` / `{:ok, _}` result for all elements
  in the given enumerable.

  Takes an enumerable or `{:ok, enumerable}` (giving `:ok` will return an error)
  and applies a callback function to each element. If all calls to the callback
  return `:ok` or `{:ok, any()}` then `all` returns `:ok`.

  If any callback returns an error, immediately stops processing and returns that error.

  If `:error` or `{:error, reason}` are given as the first argument, they are returned
  unchanged. Note that even if callbacks return `{:ok, value}`, the values are discarded
  and only `:ok` is returned — this function is for validation, not transformation.
  See `map_if/2` if you need transformation which short-circuits.

  This is useful when you need to validate that all items in a collection meet certain
  criteria before proceeding with subsequent operations.

  ## Examples

      iex> Triage.all(emails, &check_valid_email)
      :ok

      iex> Triage.all({:ok, emails}, &check_valid_email)
      {:error, :invalid_hostname}

      iex> Triage.all(:error, fn _ -> <not called> end)
      :error

      iex> Triage.all({:error, :not_found}, fn _ -> <not called> end)
      {:error, :not_found}
  """
  @spec all(value_result() | Enumerable.t(), (any() -> result())) ::
          :ok | :error | {:error, Triage.WrappedError.t()}
  def all({:ok, input}, func), do: all(input, func)
  def all(:error, _), do: :error
  def all({:error, _} = error, _), do: error

  def all(input, func) do
    for value <- input do
      case func.(value) do
        :ok ->
          nil

        {:ok, _} ->
          nil

        :error ->
          throw({:__ERRORS__, :error})

        {:error, _} = error ->
          throw({:__ERRORS__, error})

        other ->
          Validate.validate_result!(other, :strict, "Callback return")
      end
    end

    :ok
  catch
    # Wrapping throw so that callback throws will not be caught by us
    {:__ERRORS__, error} ->
      error
  end

  @doc group: "Functions > Helpers"
  @doc """
  Generates a user-friendly error message from various error types.

  Converts `{:error, reason}` tuples into human-readable messages suitable for displaying to end users.

  When the `reason` is a string, the string error message is returned.

  When the `reason` is `t:Triage.WrappedError.t/0` it unwraps the error chain and includes context information in the message.

  For exceptions and unknown error types, it
   * generates a unique error code
   * logs the error code with full error details
   * returns a generic error to the user with the error code that the user can report

  There is also logic to specifically deal with `Ecto.Changeset` validation errors
  so that you don't need to implement your own (at least as long as you're happy
  with the default behavior)

  ## Parameters

    * `reason` - The error to convert (string, exception, `%Triage.WrappedError{}`, or any other value)

  ## Examples

      iex> user_message({:error, "Invalid email"})
      "Invalid email"

      # WrappedError which was returned as a result of `wrap_context` being called in two places
      # and where the original error was `{:error, "not found"}`
      iex> user_message({:error, %Triage.WrappedError{}})
      "not found (happened while: fetching user => validating email)"

      # Ecto.Changeset with validation errors on multiple fields
      iex> user_message({:error, %Ecto.Changeset{errors: [...]}})
      "email: has invalid format, should be at least 10 character(s); name: can't be blank"

      iex> user_message({:error, %RuntimeError{message: "boom"}})
      "There was an error. Refer to code: ABC12345"

      Log generated:
      ABC12345: Could not generate user error message. Error was: #RuntimeError<...> (message: boom)
  """
  @spec user_message({:error, any()}) :: String.t()
  def user_message({:error, reason}) when is_binary(reason), do: reason

  def user_message({:error, %Ecto.Changeset{} = changeset}) do
    Triage.Ecto.format_errors(changeset)
  end

  def user_message({:error, %WrappedError{} = error}) do
    errors = WrappedError.unwrap(error)
    last_error = List.last(errors)
    context_string = Enum.map_join(errors, " => ", & &1.context)

    user_message(last_error.result) <> " (happened while: #{context_string})"
  end

  def user_message({:error, exception}) when is_exception(exception) do
    error_code = Triage.String.generate(8)

    Logger.error(
      "#{error_code}: Could not generate user error message. Error was: #{Triage.Inspect.inspect(exception)} (message: #{Results.exception_message(exception)})"
    )

    "There was an error. Refer to code: #{error_code}"
  end

  def user_message({:error, reason}) do
    error_code = Triage.String.generate(8)

    Logger.error(
      "#{error_code}: Could not generate user error message. Error was: #{Triage.Inspect.inspect(reason)}"
    )

    "There was an error. Refer to code: #{error_code}"
  end

  @doc group: "Functions > Helpers"
  @doc """
  Logs a result tuple and returns it unchanged.

  Takes a result and logs it. By default, only errors are logged.

  The `mode` argument can be either `:errors` (the default) or `:all` (logs all results)

  See [this guide](logging-json.html) for information about
  logging with JSON

  The `result` passed in can be:

   * `:ok` / `:error`
   * `{:ok, any()}` / `{:error, any()}`
   * `{:ok, ...}` / `{:error, ...}` (any sized tuple starting with :ok or :error)
  """
  @spec log(result() | tuple()) :: result() | tuple()
  def log(result, mode \\ :errors) do
    Validate.validate_result!(result, :loose)

    if mode not in [:errors, :all] do
      raise ArgumentError, "mode must be either :errors or :all (got: #{inspect(mode)})"
    end

    stacktrace = Stacktrace.calling_stacktrace()

    {message, result_details} = Map.pop(Results.details(result), :message)

    if result_details.type in ~w[error raise] || mode == :all do
      level = if(result_details.type in ~w[error raise], do: :error, else: :info)

      stacktrace_line =
        stacktrace
        |> Stacktrace.most_relevant_entry()
        |> Stacktrace.format_file_line()

      parts_string =
        [stacktrace_line, message]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(": ")

      {metadata, result_details} = Map.pop(result_details, :metadata, %{})

      metadata = Map.put(metadata, :errors_result_details, result_details)

      Logger.log(level, "[RESULT] #{parts_string}", metadata)
    end

    result
  end

  @doc group: "Functions > Helpers"
  @doc """
  Checks if a result is a success (`:ok` or `{:ok, any()}`).

  Returns `true` if the result is `:ok` or `{:ok, any()}`, `false` if it's
  `:error` or `{:error, any()}`. Raises `ArgumentError` for any other value.

  ## Examples

      iex> Triage.ok?(:ok)
      true

      iex> Triage.ok?({:ok, 42})
      true

      iex> Triage.ok?({:ok, 42, :ignore})
      true

      iex> Triage.ok?(:error)
      false

      iex> Triage.ok?({:error, :not_found})
      false

      iex> Triage.ok?({:error, :not_found, 123})
      false
  """
  def ok?(:ok), do: true
  def ok?(:error), do: false
  def ok?(result) when is_tuple(result), do: elem(result, 0) == :ok
  def ok?(result), do: Validate.validate_result!(result, :loose)

  @doc group: "Functions > Helpers"
  @doc """
  Checks if a result is an error (`:error` or `{:error, any()}`).

  Returns `true` if the result is `:error` or `{:error, any()}`, `false` if it's
  `:ok` or `{:ok, any()}`. Raises `ArgumentError` for any other value.

  ## Examples

      iex> Triage.error?(:error)
      true

      iex> Triage.error?({:error, :not_found})
      true

      iex> Triage.error?({:error, :not_found, 123})
      true

      iex> Triage.error?(:ok)
      false

      iex> Triage.error?({:ok, 42})
      false

      iex> Triage.error?({:ok, 42, :ignored})
      false
  """
  def error?(:ok), do: false
  def error?(:error), do: true
  def error?(result) when is_tuple(result), do: elem(result, 0) == :error
  def error?(result), do: Validate.validate_result!(result, :loose)

  defp result_type(:ok), do: :ok
  defp result_type(:error), do: :error
  defp result_type(result) when is_tuple(result) and elem(result, 0) == :ok, do: :ok
  defp result_type(result) when is_tuple(result) and elem(result, 0) == :error, do: :error
  defp result_type(_), do: nil
end
