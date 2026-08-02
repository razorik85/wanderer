defmodule WandererApp.MapConnectionHistoryRepo do
  @moduledoc false

  use WandererApp, :repository

  require Logger

  @logger Application.compile_env(:wanderer_app, :logger)

  def get_by_id(id), do: WandererApp.Api.MapConnectionHistory.by_id(id)

  def get_by_map(map_id),
    do: WandererApp.Api.MapConnectionHistory.by_map(%{map_id: map_id})

  def annotate_open(_connection_id, nil), do: :ok

  def annotate_open(connection_id, character_id) do
    update_history(connection_id, :annotate_open, %{opened_by_character_id: character_id})
  end

  def prepare_close(connection_id, opts \\ []) do
    attrs =
      %{
        closure_reason: Keyword.get(opts, :closure_reason, "deleted"),
        closed_by_character_id: Keyword.get(opts, :closed_by_character_id),
        closed_by_user_id: Keyword.get(opts, :closed_by_user_id)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    update_history(connection_id, :prepare_close, attrs)
  end

  defp update_history(connection_id, action, attrs) do
    case get_by_id(connection_id) do
      {:ok, history} ->
        case apply(WandererApp.Api.MapConnectionHistory, action, [history, attrs]) do
          {:ok, _history} ->
            :ok

          {:error, error} ->
            @logger.error(
              "Failed to update connection history #{connection_id}: #{inspect(error, pretty: true)}"
            )

            :ok
        end

      {:error, error} ->
        @logger.warning(
          "Connection history #{connection_id} was not found: #{inspect(error, pretty: true)}"
        )

        :ok
    end
  end
end
