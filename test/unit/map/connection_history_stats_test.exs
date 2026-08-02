defmodule WandererApp.Map.ConnectionHistoryStatsTest do
  use WandererApp.DataCase, async: false

  alias WandererApp.Api.MapChainPassages
  alias WandererApp.Map.ConnectionHistoryStats
  alias WandererApp.MapConnectionRepo

  setup do
    user = create_user()
    character = create_character(%{user_id: user.id})
    map = create_map(%{owner_id: character.id})

    source =
      create_solar_system(%{
        solar_system_id: 39_900_001,
        solar_system_name: "Origin",
        class_title: "Class 2"
      })

    first_target =
      create_solar_system(%{
        solar_system_id: 39_900_002,
        solar_system_name: "First Target",
        class_title: "Class 3"
      })

    second_target =
      create_solar_system(%{
        solar_system_id: 39_900_003,
        solar_system_name: "Second Target",
        class_title: "Low Sec"
      })

    {:ok,
     user: user,
     character: character,
     map: map,
     source: source,
     first_target: first_target,
     second_target: second_target}
  end

  test "aggregates wormhole lifecycles, destinations, routes and passages per map", context do
    %{map: map, character: character} = context

    {:ok, first_connection} =
      MapConnectionRepo.create(%{
        map_id: map.id,
        solar_system_source: context.source.solar_system_id,
        solar_system_target: context.first_target.solar_system_id,
        type: 0,
        wormhole_type: "O477",
        mass_status: 0,
        time_status: 0
      })

    create_passage(
      map.id,
      character.id,
      context.source.solar_system_id,
      context.first_target.solar_system_id
    )

    create_passage(
      map.id,
      character.id,
      context.first_target.solar_system_id,
      context.source.solar_system_id
    )

    assert {:ok, first_connection} =
             MapConnectionRepo.update_mass_status(first_connection, %{mass_status: 2})

    assert :ok =
             MapConnectionRepo.destroy(map.id, first_connection, closure_reason: "collapsed")

    {:ok, _second_connection} =
      MapConnectionRepo.create(%{
        map_id: map.id,
        solar_system_source: context.source.solar_system_id,
        solar_system_target: context.second_target.solar_system_id,
        type: 0,
        wormhole_type: "B274",
        mass_status: 0,
        time_status: 0
      })

    create_passage(
      map.id,
      character.id,
      context.source.solar_system_id,
      context.second_target.solar_system_id
    )

    {:ok, _stargate_connection} =
      MapConnectionRepo.create(%{
        map_id: map.id,
        solar_system_source: context.first_target.solar_system_id,
        solar_system_target: context.second_target.solar_system_id,
        type: 1
      })

    other_user = create_user()
    other_character = create_character(%{user_id: other_user.id})
    other_map = create_map(%{owner_id: other_character.id})

    {:ok, _other_connection} =
      MapConnectionRepo.create(%{
        map_id: other_map.id,
        solar_system_source: context.source.solar_system_id,
        solar_system_target: context.first_target.solar_system_id,
        type: 0,
        wormhole_type: "O477"
      })

    statistics = ConnectionHistoryStats.get(map.id, "ALL")

    assert statistics.summary.connections == 2
    assert statistics.summary.active == 1
    assert statistics.summary.closed == 1
    assert statistics.summary.collapsed == 1
    assert statistics.summary.distinct_destinations == 2
    assert statistics.summary.passages == 3
    assert statistics.summary.reduced == 1
    assert statistics.summary.critical == 1

    first_destination =
      Enum.find(
        statistics.destinations,
        &(&1.solar_system_id == context.first_target.solar_system_id)
      )

    assert first_destination.name == "First Target"
    assert first_destination.connections == 1
    assert first_destination.passages == 2

    first_route =
      Enum.find(statistics.routes, &(&1.target_id == context.first_target.solar_system_id))

    assert first_route.source_name == "Origin"
    assert first_route.target_name == "First Target"
    assert first_route.passages == 2

    assert %{name: "O477", count: 1} in statistics.wormhole_types
    assert %{name: "B274", count: 1} in statistics.wormhole_types
    assert %{reason: "collapsed", count: 1} in statistics.closure_reasons
  end

  test "normalizes unsupported periods", _context do
    assert ConnectionHistoryStats.normalize_period("7D") == "7D"
    assert ConnectionHistoryStats.normalize_period("invalid") == "30D"
    assert ConnectionHistoryStats.normalize_period(nil) == "30D"
  end

  test "allows owners and ACL viewers while rejecting unrelated users", %{
    map: map,
    user: owner_user,
    character: owner_character
  } do
    owner_user = Ash.load!(owner_user, :characters)

    assert {:ok, %{id: map_id}} =
             WandererApp.Maps.check_user_can_view_connections(map.slug, owner_user)

    assert map_id == map.id

    viewer_user = create_user()
    viewer_character = create_character(%{user_id: viewer_user.id})
    access_list = create_access_list(owner_character.id)

    create_access_list_member(access_list.id, %{
      eve_character_id: viewer_character.eve_id,
      role: :viewer
    })

    create_map_access_list(map.id, access_list.id)

    viewer_user = Ash.load!(viewer_user, :characters)

    assert {:ok, %{id: ^map_id}} =
             WandererApp.Maps.check_user_can_view_connections(map.slug, viewer_user)

    stranger_user = create_user()
    _stranger_character = create_character(%{user_id: stranger_user.id})
    stranger_user = Ash.load!(stranger_user, :characters)

    assert {:error, :not_authorized} =
             WandererApp.Maps.check_user_can_view_connections(map.slug, stranger_user)
  end

  defp create_passage(map_id, character_id, source_id, target_id) do
    {:ok, passage} =
      MapChainPassages.new(%{
        map_id: map_id,
        character_id: character_id,
        ship_type_id: 11_984,
        solar_system_source_id: source_id,
        solar_system_target_id: target_id
      })

    passage
  end
end
