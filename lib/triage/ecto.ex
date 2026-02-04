# Helpers for working with Ecto changesets in Triage.

defmodule Triage.Ecto do
  @moduledoc false

  @doc """
  Formats an Ecto.Changeset's errors into a user-friendly error message.

  Converts validation errors into human-readable messages, sorted by field name.
  Base errors (errors without a specific field) are displayed without a field prefix.
  """
  @spec format_errors(Ecto.Changeset.t()) :: String.t()
  def format_errors(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        format_error_message(msg, opts)
      end)

    errors
    |> Enum.sort_by(fn {field, _messages} -> field end)
    |> Enum.map_join("; ", fn {field, messages} ->
      message_string =
        messages
        |> Enum.sort()
        |> Enum.join(", ")

      if(field in [:base, nil], do: "", else: "#{field}: ") <> message_string
    end)
  end

  defp format_error_message(msg, opts) do
    validation = Keyword.get(opts, :validation)

    case validation do
      :subset ->
        enum = Keyword.get(opts, :enum)
        "expected to be a subset of #{inspect(enum)}"

      :inclusion ->
        enum = Keyword.get(opts, :enum)
        "must be one of: #{inspect(enum)}"

      :exclusion ->
        enum = Keyword.get(opts, :enum)
        "cannot be one of: #{inspect(enum)}"

      _ ->
        # For all other validations, interpolate placeholders
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", inspect(value))
        end)
    end
  end
end
