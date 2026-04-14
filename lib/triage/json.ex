defmodule Triage.JSON do
  @moduledoc false

  # Helpers for JSON output
  #
  # This library doesn't output JSON itself, but it's useful to be able to turn
  # terms into a JSON-friendly format

  defprotocol Shrink do
    @moduledoc false

    @fallback_to_any true

    # This function exists to reduce the data that is sent out (logs/telemetry) to
    # the fields that are the most useful for debugging.  Currently that is
    # just identifying fields (`id` or `*_id` fields, along with `type` fields
    # to identify structs), but it could be other things later if we can
    # algorithmically identify fields which would be generically helpful when
    # debugging

    @spec shrink(t) :: term()
    def shrink(value)
  end
end

defimpl Triage.JSON.Shrink, for: Triage.WrappedError do
  @moduledoc false

  def shrink(exception) do
    errors = Triage.WrappedError.unwrap(exception)
    last_error = List.last(errors)

    contexts =
      Enum.map(errors, fn error ->
        %{
          label: Triage.JSON.Shrink.shrink(error.context),
          stacktrace: format_stacktrace(error.stacktrace),
          metadata: Triage.JSON.Shrink.shrink(error.metadata)
        }
      end)

    {:error, reason} = last_error.result

    %{
      __root_reason__: Triage.JSON.Shrink.shrink(reason),
      __contexts__: contexts
    }
  end

  # Turns stacktrace into an array of strings for readability in logs
  def format_stacktrace(stacktrace) do
    stacktrace
    |> Exception.format_stacktrace()
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
  end
end

# Fallback to Any so that apps can implement overrides
defimpl Triage.JSON.Shrink, for: Any do
  def shrink(exception) when is_exception(exception) do
    exception
    |> Map.from_struct()
    |> Map.delete(:__exception__)
    |> Map.delete(:message)
    |> Map.put(:__struct__, Macro.to_string(exception.__struct__))
    |> Map.put(:__message__, Exception.message(exception))
  end

  def shrink(%mod{} = struct) do
    map =
      struct
      |> Map.from_struct()
      |> Triage.JSON.Shrink.shrink()

    if map_size(map) > 0 do
      map
      |> Map.put(:__struct__, Macro.to_string(mod))
      |> customize_fields(mod, struct)
    else
      map
    end
  end

  def shrink(map) when is_map(map) do
    map
    |> Enum.map(fn
      {key, value} when is_pid(key) -> {Kernel.inspect(key), value}
      {key, value} -> {key, value}
    end)
    |> Enum.map(fn
      {key, value}
      when is_map(value) or is_list(value) or is_tuple(value) or is_function(value) ->
        {key, Triage.JSON.Shrink.shrink(value)}

      {key, value} ->
        {key, value}
    end)
    |> Enum.filter(fn
      {_, :__LIST_WITHOUT_ITEMS__} ->
        false

      # {_, nil} ->
      #   !sub_value?

      {key, _} when key in [:id, "id", :name, "name"] ->
        true

      {key, value} ->
        # !String.Chars.impl_for(key) or
        Regex.match?(~r/[a-z](_id|Id|ID)$/, to_string(key)) or
          (is_map(value) and map_size(value) > 0) or
          is_list(value)
    end)
    |> Enum.into(%{})
  end

  def shrink(list) when is_list(list) do
    if length(list) > 0 and Keyword.keyword?(list) do
      list
      |> Enum.into(%{})
      |> Triage.JSON.Shrink.shrink()
    else
      Enum.map(list, &Triage.JSON.Shrink.shrink(&1))
    end
  end

  # Not 100% sure about this approach, but trying it for now 🤷‍♂️
  def shrink(tuple) when is_tuple(tuple), do: Kernel.inspect(tuple)

  def shrink(func) when is_function(func) do
    function_info = Function.info(func)

    "&#{Kernel.inspect(function_info[:module])}.#{function_info[:name]}/#{function_info[:arity]}"
  end

  def shrink(string) when is_binary(string) do
    case Jason.encode(string) do
      {:ok, _} -> string
      {:error, _} -> inspect(string)
    end
  end

  def shrink(pid) when is_pid(pid), do: Kernel.inspect(pid)

  def shrink(value), do: value

  defp customize_fields(map, MyApp.Accounts.User, original) do
    map
    |> Map.put(:name, original.name)
    |> Map.put(:is_admin, original.is_admin)
  end

  defp customize_fields(map, _, _), do: map
end
