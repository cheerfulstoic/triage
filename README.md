**IMPORTANT NOTE**: This library's API and documentation is very fleshed out. But much of this library is a work-in-progress conceptually. Please consider everything as potentially open to change!

# Triage

A lightweight Elixir library for enhanced handling of **results** (`{:ok, _}` / `:ok` / `{:error, _}` / `:error`) with context wrapping, logging, and user message generation.

## Features

This package provides three levels of working with errors which are all **usable independently**, but which all complement each other.

- **Context Wrapping**: Add meaningful context to errors as they bubble up through your application
- **Result Logging**: Log errors (and optionally successes) with file/line information
- **User-friendly errors**: Be able to collapse errors into a single user error message
- **Error enumeration**: functions like `map_if`, `find_value`, and `all` help deal with enumerations over data where each iteration may succeed or fail.
- **Error control flow**: `ok_then` and `error_then` functions help control and transform results

Design goals:

- Standard results (`:ok`, `:error`, `{:ok, term()}`, `{:error, term()}` with only one value in tuples)
- Avoid macros for easy pick-up-and-use throughout a codebase (i.e. no need for `require`)
- Variety of small tools which work well together (like UNIX commands)

See the [Philosophy](https://hexdocs.pm/triage/philosophy.html) section of the docs for more details.

## Examples

### Contexts

When an error is returned (e.g. in a tuple, as opposed to being raised), often that error can be passed up a stack and it becomes unclear where the error came from. Triage offers a `wrap_context` function to attach a context string and/or metadata to errors via a `WrappedError` exception struct.

```elixir
defmodule MyApp.OrderProcessor do
  def process_payment(order) do
    with {:ok, payment_method} <- fetch_payment_method(order),
         {:ok, charge} <- charge_payment(payment_method, order.amount) do
      {:ok, charge}
    end
    |> Triage.wrap_context("process payment", %{order_id: order.id, order_amount: order.amount})
  end
  # ...
end

defmodule MyApp.OrderService do
  def complete_order(order_id) do
    fetch_order(order_id)
    |> MyApp.OrderProcessor.process_payment()
    |> Triage.wrap_context("complete order")
  end
  # ...
end
```

But an error wrapped with a context isn't so useful by itself.  Your code can look at the `WrappedError` if you'd like, but it can be most useful with the output tools below.

(Also, make sure to see the [Contexts section of the docs](https://hexdocs.pm/triage/contexts.html) for more information)

### Output

Error results that you get back can be a mess. Often when you get an error tuple it comes back from a tree of nested calls and the reason value could be of many types (string, atom, etc...).  So it's useful to have tools which let you not worry about it so much. Below is an example of using `Triage.log` to output logs:

```elixir
def show(conn, %{"order_id" => order_id}) do
  order_id = String.to_integer(order_id)

  MyApp.complete_order(order_id)
  |> Triage.log()
  # ...
```

By default `Triage.log` will only output error cases (pass in `:all` to log `:ok` results as well), so if this case is important we can have a log of how it went wrong. Also note that any metadata given to `log` is also assigned to the [Logger metadata](https://hexdocs.pm/logger/Logger.html#module-metadata) in addition to being outputted (helpful for filtering logs).

The output can be as simple as this in the case of an atom given as the error reason:

```
[RESULT] lib/my_app/order_controller.ex:41: {:error, :order_was_invalid}
```

But if `Triage.wrap_context` is used, we can get even more details out:

```
[error] [RESULT] lib/my_app/order_service.ex:15: {:error, :payment_declined}
  [CONTEXT] lib/my_app/order_service.ex:15: complete order
  [CONTEXT] lib/my_app/order_processor.ex:8: process payment | %{order_id: 12345, amount: 99.99}
```

Note that if you'd prefer to output JSON logs, there is some [information in the docs](https://hexdocs.pm/triage/logging-json.html)
Additionally, the `Triage.user_message` function will extract a message from the error if possible.  If not possible, the user will be given a generic error with a randomly generated short code which can be matched to a log entry with details about the error.

```elixir
def show(conn, %{"order_id" => order_id}) do
  order_id = String.to_integer(order_id)

  MyApp.complete_order(order_id)
  |> case do
    {:ok, value} ->
      # ...

    {:error, _} = error ->
      conn
      |> put_status(400)
      |> json(%{error: Triage.user_message(error)})
  end
  # ...
```

The `user_message` function even supports a default implementation to provide `Ecto.Changeset` errors, so if it gets a changeset value in an error then users will get a reasonable value such as "age: must be greater than 18; email: can't be blank".

See the [Outputs section of the docs](https://hexdocs.pm/triage/outputs.html) for more information.

### Enumeration

`triage` has a set of functions to help when you have a series of step which might succeed or fail.  As an example, you may want to build up a list, but return an error if anything fails.

```elixir
  defp validate_each_metric(metrics, query) do
    Enum.reduce_while(metrics, {:ok, []}, fn metric, {:ok, acc} ->
      case validate_metric(metric, query) do
        {:ok, metric} -> {:cont, {:ok, acc ++ [metric]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
```

The `Triage.map_if` function is one tool available:

```elixir
  defp validate_each_metric(metrics, query) do
    # Returns {:ok, [...]} where the original returned just [...]
    Triage.map_if(metrics, & validate_metric(&1, query))
  end
```

For more functions and examples, see the [Enumerating Errors section of the docs](https://hexdocs.pm/triage/enumerating-errors.html).

### Control Flow

`triage`'s two control flow tools (`ok_then` and `error_then`) can both be shown via an HTTP request example:

```elixir
fetch_bill(bill_id)
|> Triage.ok_then(& HTTPoison.get(&1.pdf_url))
|> Triage.ok_then(fn
  %HTTPoison.Response{status_code: 200, body: body} ->
    body

  %HTTPoison.Response{status_code: 404, body: body} ->
    {:error, "Server result not found"}
end)
|> Triage.error_then(fn
    %HTTPoison.Error{reason: :nxdomain} ->
      "Server domain not found"

    %HTTPoison.Error{reason: :econnrefused} ->
      "Server connection refused"

    %HTTPoison.Error{reason: reason} ->
      "Unexpected error connecting to server: #{inspect(reason)}"
end)
```

The `Triage.ok_then` function works on `:ok` results, ignoring errors.  Values that are returned from the callback are automatically wrapped in an `{:ok, _}` tuple, though any `:error` or `{:error, term()}` returned will be returned as an error.

The `Triage.error_then` function is the opposite: working on `:error` reasons and returning new reasons to be wrapped in an `{:error, _}` tuple.  If an `:ok` or `{:ok, _}` result is returned, then the error is ignored and `Triage.error_then` will return that success.

Additionally there are `tap_ok` and `tap_error` function which allow you to execute side-effects (see also Elixir's [`Kernel.then/2`](https://hexdocs.pm/elixir/Kernel.html#then/2) and [`Kernel.tap/2`](https://hexdocs.pm/elixir/Kernel.html#tap/2) functions which are analogous to the above).

Make sure to see the [Control Flow section of the docs](https://hexdocs.pm/triage/control-flow.html) for more information.

Also, many people wonder why they shouldn't just use `with` instead of `ok_then` / `error_then`.  There is a [section in the docs](https://hexdocs.pm/triage/comparison-to-with.html) for that too!

## Installation

Add `triage` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:triage, "~> 0.5.0"}
  ]
end
```

For various reasons, `triage` requires at least version `1.15` of Elixir.

## Usage

See [the docs](https://hexdocs.pm/triage) for detailed information about the different tools available.

## Development

Run tests:

Run tests in watch mode (uses [`mix_test_interactive`](https://hex.pm/packages/mix_test_interactive):

```bash
mix test.interactive
```

Or just:

```bash
mix test
```

## License

Copyright (c) 2025

This work is free. You can redistribute it and/or modify it under the
terms of the MIT License. See the LICENSE file for more details.
