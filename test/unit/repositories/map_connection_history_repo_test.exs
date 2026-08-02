defmodule WandererApp.MapConnectionHistoryRepoTest do
  use WandererApp.DataCase, async: false

  alias WandererApp.Api.MapChainPassages
  alias WandererApp.MapConnectionHistoryRepo
  alias WandererApp.MapConnectionRepo

  setup do
    user = create_user()
    character = create_character(%{user_id: user.id})
    map = create_map(%{owner_id: character.id})

    {:ok, user: user, character: character, map: map}
  end

  test "keeps a lifecycle snapshot and its passages after the live connection is deleted", %{
    user: user,
    character: character,
    map: map
  } do
    {:ok, connection} =
      MapConnectionRepo.create(
        %{
          map_id: map.id,
          solar_system_source: 31_000_409,
          solar_system_target: 31_001_306,
          type: 0,
          ship_size_type: 2,
          mass_status: 0,
          time_status: 0,
          wormhole_type: "O477"
        },
        opened_by_character_id: character.id
      )

    assert {:ok, history} = MapConnectionHistoryRepo.get_by_id(connection.id)
    assert history.id == connection.id
    assert history.map_id == map.id
    assert history.opened_by_character_id == character.id
    assert history.initial_mass_status == 0
    assert history.mass_status == 0
    assert history.closed_at == nil

    {:ok, passage} =
      MapChainPassages.new(%{
        map_id: map.id,
        character_id: character.id,
        ship_type_id: 11_984,
        ship_name: "Test ship",
        solar_system_source_id: 31_000_409,
        solar_system_target_id: 31_001_306
      })

    assert passage.connection_history_id == connection.id

    assert {:ok, connection} =
             MapConnectionRepo.update_mass_status(connection, %{mass_status: 1})

    assert {:ok, connection} =
             MapConnectionRepo.update_time_status(connection, %{time_status: 5})

    assert {:ok, history} = MapConnectionHistoryRepo.get_by_id(connection.id)
    assert history.eol_at == nil

    assert {:ok, connection} =
             MapConnectionRepo.update_time_status(connection, %{time_status: 1})

    assert {:ok, connection} =
             MapConnectionRepo.update_mass_tracking(connection, %{
               mass_tracking_started_at: DateTime.utc_now(),
               source_signature_eve_id: "ABC-123"
             })

    assert {:ok, history} = MapConnectionHistoryRepo.get_by_id(connection.id)
    assert history.initial_mass_status == 0
    assert history.mass_status == 1
    assert history.time_status == 1
    assert history.reduced_at != nil
    assert history.eol_at != nil
    assert history.source_signature_eve_id == "ABC-123"

    assert :ok =
             MapConnectionRepo.destroy(map.id, connection,
               closure_reason: "collapsed",
               closed_by_character_id: character.id,
               closed_by_user_id: user.id
             )

    assert {:ok, history} = MapConnectionHistoryRepo.get_by_id(connection.id)
    assert history.closure_reason == "collapsed"
    assert history.closed_at != nil
    assert history.closed_by_character_id == character.id
    assert history.closed_by_user_id == user.id

    assert {:ok, stored_passage} = MapChainPassages.by_id(passage.id)
    assert stored_passage.connection_history_id == history.id
  end

  test "separates a new connection between the same systems into a new lifecycle", %{
    character: character,
    map: map
  } do
    attrs = %{
      map_id: map.id,
      solar_system_source: 31_000_409,
      solar_system_target: 30_000_142,
      type: 0,
      ship_size_type: 2,
      mass_status: 0,
      time_status: 0
    }

    assert {:ok, first_connection} =
             MapConnectionRepo.create(attrs, opened_by_character_id: character.id)

    assert :ok =
             MapConnectionRepo.destroy(map.id, first_connection, closure_reason: "auto_cleanup")

    assert {:ok, second_connection} =
             MapConnectionRepo.create(attrs, opened_by_character_id: character.id)

    refute first_connection.id == second_connection.id

    {:ok, passage} =
      MapChainPassages.new(%{
        map_id: map.id,
        character_id: character.id,
        ship_type_id: 11_984,
        solar_system_source_id: 30_000_142,
        solar_system_target_id: 31_000_409
      })

    assert passage.connection_history_id == second_connection.id

    assert {:ok, first_history} = MapConnectionHistoryRepo.get_by_id(first_connection.id)
    assert {:ok, second_history} = MapConnectionHistoryRepo.get_by_id(second_connection.id)
    assert first_history.closure_reason == "auto_cleanup"
    assert first_history.closed_at != nil
    assert second_history.closed_at == nil
  end

  test "backfills the first jump when it is recorded immediately before the connection", %{
    character: character,
    map: map
  } do
    {:ok, passage} =
      MapChainPassages.new(%{
        map_id: map.id,
        character_id: character.id,
        ship_type_id: 11_984,
        solar_system_source_id: 31_000_409,
        solar_system_target_id: 31_000_808
      })

    assert passage.connection_history_id == nil

    assert {:ok, connection} =
             MapConnectionRepo.create(%{
               map_id: map.id,
               solar_system_source: 31_000_409,
               solar_system_target: 31_000_808,
               type: 0,
               ship_size_type: 2
             })

    assert {:ok, stored_passage} = MapChainPassages.by_id(passage.id)
    assert stored_passage.connection_history_id == connection.id
  end
end
