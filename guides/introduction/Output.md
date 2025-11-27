# Output

## Logging

The `log/2` function logs results and passes them through unchanged, making it perfect for debugging pipelines.

### Logging Errors Only (the default)

```elixir
defmodule API.UserController do
  def create(conn, params) do
    Users.create_user(params)
    # Only logs if there's an error
    |> Triage.log()
    # You can also pass mode: :errors (the default)
    # |> Triage.log(mode: :errors)
    |> case do
      {:ok, user} ->
        conn
        |> render("user.json", user: user)
      # Ideally we should return a useful error... see below!
      {:error, _} ->
        conn
        |> put_status(400)
        |> json(%{error: "Unable to create user"})
    end
  end
end
```

When `Users.create_user` returns an error, a log is written at the `error` log level:

```
# [error] [RESULT] lib/api/user_controller.ex:4: {:error, #Ecto.Changeset<...>}
```

### Logging All Results (`mode: :all`)

In the case above, instead of calling `|> log(mode: :errors)`  we could call `|> log(mode: :all)`. In that case we could get the error log above, or we could get a success result written to the log at the `info` level:

```
# [info] [RESULT] lib/api/user_controller.ex:4: {:ok, %MyApp.Users.User{...}}
```

### Contexts

When errors occur deep in your application's call stack, it can be challenging to understand where your errors are coming from. The `wrap_context/3` function allows you to add contextual information at multiple levels, building up a trail of breadcrumbs as errors bubble up.

Here's an example showing how contexts accumulate across different modules:

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
    |> MyApp.OrderProcessor.process_payment(order)
    |> Triage.wrap_context("complete order")
  end
  # ...
end
```

When an error occurs in the payment processing, logging it will show the full context chain:

```elixir
def show(conn, %{"order_id" => order_id}) do
  order_id = String.to_integer(order_id)

  MyApp.complete_order(order_id)
  |> Triage.log()
  # ...

# Log output:
# [error] [RESULT] lib/my_app/order_service.ex:15: {:error, :payment_declined}
#     [CONTEXT] lib/my_app/order_service.ex:15: complete order
#     [CONTEXT] lib/my_app/order_processor.ex:8: process payment | %{order_id: 12345, amount: 99.99}
```

This makes it easy to trace exactly what your application was doing when the error occurred, including both descriptive labels and relevant data.

## User-friendly output

It's possible that you might have some code, be it in a LiveView, controller, background worker, etc... Often code at this "top level" might have called a series of functions which call a further series of functions, all of which can potentially return ok/error results.  When getting back `{:error, _}` tuples specifically, often the value inside of the tuple could be one of many things (e.g. a string/atom/struct/exception, etc...) Often the simplest thing to do is to return something like `There was an error: #{inspect(reason)}`, but that value often won't make sense to the user.  So we should find a way to make it human-readable, whenever possible.

```elixir
defmodule MyAppWeb.UserController do
  def checkout(conn, params) do
    MyApp.Users.create_user(params)
    |> case do
      {:ok, result} ->
        conn
        |> render("checkout.json", result: result)
      # Ideally we should return a useful error... see below!
      {:error, _} = error ->
        conn
        |> put_status(400)
        |> json(%{error: Triage.user_message(error)})
    end
    # ...
```

In this case, you could imagine that `MyApp.Users.create_user(params)` could return one of the following errors:

```elixir
# A string
{:error, "Could not contact tracking server"}
# An atom
{:error, :user_not_found}
# A struct containing errors
{:error, %Ecto.Changeset{...}}
# An exception value
{:error, %Jason.DecodeError{...}
```

`Triage.user_message` always turns the `error` into a string and does it's best to extract the appropriate data for a human-readable string.

Additionally, if you use `Triage.wrap_context`, additional information from the `WrappedError` will be available to help describe the error.
