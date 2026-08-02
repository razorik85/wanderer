defmodule WandererApp.MapConnectionRepo do
  use WandererApp, :repository

  require Logger

  @logger Application.compile_env(:wanderer_app, :logger)

  def get_by_map(map_id),
    do: WandererApp.Api.MapConnection.read_by_map(%{map_id: map_id})

  def get_by_locations(map_id, solar_system_source, solar_system_target) do
    WandererApp.Api.MapConnection.by_locations(%{
      map_id: map_id,
      solar_system_source: solar_system_source,
      solar_system_target: solar_system_target
    })
    |> case do
      {:ok, connections} ->
        {:ok, connections}

      {:error, %Ash.Error.Query.NotFound{}} ->
        {:ok, []}

      {:error, error} ->
        @logger.error("Failed to get connections: #{inspect(error, pretty: true)}")
        {:error, error}
    end
  end

  def create(connection, opts \\ []) do
    case WandererApp.Api.MapConnection.create(connection) do
      {:ok, created_connection} = result ->
        WandererApp.MapConnectionHistoryRepo.annotate_open(
          created_connection.id,
          Keyword.get(opts, :opened_by_character_id)
        )

        result

      error ->
        error
    end
  end

  def create!(connection, opts \\ []) do
    created_connection = WandererApp.Api.MapConnection.create!(connection)

    WandererApp.MapConnectionHistoryRepo.annotate_open(
      created_connection.id,
      Keyword.get(opts, :opened_by_character_id)
    )

    created_connection
  end

  def destroy(map_id, connection, opts \\ [])

  def destroy(map_id, connection, opts) when not is_nil(connection) do
    {:ok, from_connections} =
      get_by_locations(map_id, connection.solar_system_source, connection.solar_system_target)

    {:ok, to_connections} =
      get_by_locations(map_id, connection.solar_system_target, connection.solar_system_source)

    [from_connections ++ to_connections]
    |> List.flatten()
    |> tap(fn connections ->
      Enum.each(connections, fn item ->
        WandererApp.MapConnectionHistoryRepo.prepare_close(item.id, opts)
      end)
    end)
    |> bulk_destroy!()
    |> case do
      :ok ->
        :ok

      error ->
        @logger.error("Failed to remove connections from map: #{inspect(error, pretty: true)}")
        :ok
    end
  end

  def destroy(_map_id, _connection, _opts), do: :ok

  def destroy!(connection, opts \\ []) do
    WandererApp.MapConnectionHistoryRepo.prepare_close(connection.id, opts)
    WandererApp.Api.MapConnection.destroy!(connection)
  end

  def bulk_destroy!(connections) do
    connections
    |> WandererApp.Api.MapConnection.destroy!()
    |> case do
      %Ash.BulkResult{status: :success} ->
        :ok

      error ->
        error
    end
  end

  def update_time_status(connection, update),
    do:
      connection
      |> WandererApp.Api.MapConnection.update_time_status(update)

  def update_type(connection, update),
    do:
      connection
      |> WandererApp.Api.MapConnection.update_type(update)

  def update_mass_status(connection, update),
    do:
      connection
      |> WandererApp.Api.MapConnection.update_mass_status(update)

  def update_mass_tracking(connection, update),
    do:
      connection
      |> WandererApp.Api.MapConnection.update_mass_tracking(update)

  def update_ship_size_type(connection, update),
    do:
      connection
      |> WandererApp.Api.MapConnection.update_ship_size_type(update)

  def update_locked(connection, update),
    do:
      connection
      |> WandererApp.Api.MapConnection.update_locked(update)

  def update_custom_info(connection, update),
    do:
      connection
      |> WandererApp.Api.MapConnection.update_custom_info(update)

  def update_wormhole_type(connection, update),
    do:
      connection
      |> WandererApp.Api.MapConnection.update_wormhole_type(update)

  def get_by_id(map_id, id) do
    # Use read_by_map action which doesn't have the FilterConnectionsByActorMap preparation
    # that was causing "filter being false" errors in tests
    require Ash.Query

    WandererApp.Api.MapConnection
    |> Ash.Query.for_read(:read_by_map, %{map_id: map_id})
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, conn} -> {:ok, conn}
      {:error, _} -> {:error, :not_found}
    end
  end
end
