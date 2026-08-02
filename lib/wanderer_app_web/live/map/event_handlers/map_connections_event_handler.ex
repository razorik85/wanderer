defmodule WandererAppWeb.MapConnectionsEventHandler do
  use WandererAppWeb, :live_component
  use Phoenix.Component
  require Logger

  alias WandererAppWeb.{MapEventHandler, MapCoreEventHandler}

  def handle_server_event(%{event: :update_connection, payload: connection}, socket),
    do:
      socket
      |> MapEventHandler.push_map_event(
        "update_connection",
        MapEventHandler.map_ui_connection(connection)
      )

  def handle_server_event(%{event: :remove_connections, payload: connections}, socket) do
    connection_ids =
      connections |> Enum.map(&MapEventHandler.map_ui_connection/1) |> Enum.map(& &1.id)

    socket
    |> MapEventHandler.push_map_event(
      "remove_connections",
      connection_ids
    )
  end

  def handle_server_event(%{event: :add_connection, payload: connection}, socket) do
    connections = [MapEventHandler.map_ui_connection(connection)]

    socket
    |> MapEventHandler.push_map_event(
      "add_connections",
      connections
    )
  end

  def handle_server_event(
        %{
          event: :passage_mass_required,
          payload: %{passage_id: passage_id, character_id: character_id}
        },
        %{
          assigns: %{
            current_user: current_user,
            map_id: map_id
          }
        } = socket
      ) do
    owns_character? =
      Enum.any?(current_user.characters, fn character ->
        "#{character.id}" == "#{character_id}"
      end)

    with true <- owns_character?,
         {:ok, passage} <- WandererAppWeb.HandlerAuth.authorize_passage(passage_id, map_id),
         {:ok, character} <- WandererApp.Character.get_character(character_id) do
      passage =
        passage
        |> Map.take([:id, :inserted_at, :mass, :mass_confirmed_at, :mass_confirmed_by_id])
        |> Map.put(:from, true)
        |> Map.put(:character, MapEventHandler.map_ui_character_stat(character))
        |> Map.put(
          :ship,
          WandererApp.Character.get_ship(%{
            ship: passage.ship_type_id,
            ship_name: passage.ship_name
          })
        )

      MapEventHandler.push_map_event(socket, "passage_mass_required", passage)
    else
      _ -> socket
    end
  end

  def handle_server_event(event, socket),
    do: MapCoreEventHandler.handle_server_event(event, socket)

  def handle_ui_event(
        "manual_add_connection",
        %{"source" => solar_system_source_id, "target" => solar_system_target_id} = _event,
        %{
          assigns: %{
            map_id: map_id,
            current_user: %{id: current_user_id},
            main_character_id: main_character_id,
            has_tracked_characters?: true,
            user_permissions: %{add_connection: true}
          }
        } =
          socket
      )
      when not is_nil(main_character_id) do
    solar_system_source_id_int = String.to_integer(solar_system_source_id)
    solar_system_target_id_int = String.to_integer(solar_system_target_id)

    map_id
    |> WandererApp.Map.Server.add_connection(%{
      solar_system_source_id: solar_system_source_id_int,
      solar_system_target_id: solar_system_target_id_int,
      character_id: main_character_id
    })

    WandererApp.User.ActivityTracker.track_map_event(:map_connection_added, %{
      character_id: main_character_id,
      user_id: current_user_id,
      map_id: map_id,
      solar_system_source_id: solar_system_source_id_int,
      solar_system_target_id: solar_system_target_id_int
    })

    {:noreply, socket}
  end

  def handle_ui_event(
        "manual_delete_connection",
        %{"source" => solar_system_source_id, "target" => solar_system_target_id} = _event,
        %{
          assigns: %{
            map_id: map_id,
            current_user: %{id: current_user_id},
            main_character_id: main_character_id,
            has_tracked_characters?: true,
            map_user_settings: map_user_settings,
            user_permissions: %{delete_connection: true}
          }
        } =
          socket
      )
      when not is_nil(main_character_id) do
    solar_system_source_id = solar_system_source_id |> String.to_integer()
    solar_system_target_id = solar_system_target_id |> String.to_integer()

    map_id
    |> WandererApp.Map.Server.delete_connection(%{
      solar_system_source_id: solar_system_source_id,
      solar_system_target_id: solar_system_target_id,
      character_id: main_character_id,
      user_id: current_user_id,
      closure_reason: "manual"
    })

    delete_connection_with_sigs =
      map_user_settings
      |> WandererApp.MapUserSettingsRepo.to_form_data!()
      |> WandererApp.MapUserSettingsRepo.get_boolean_setting("delete_connection_with_sigs")

    if delete_connection_with_sigs do
      source_system =
        WandererApp.Map.find_system_by_location(
          map_id,
          %{solar_system_id: solar_system_source_id}
        )

      target_system =
        WandererApp.Map.find_system_by_location(
          map_id,
          %{solar_system_id: solar_system_target_id}
        )

      if not is_nil(target_system.linked_sig_eve_id) do
        {:ok, signatures} =
          WandererApp.Api.MapSystemSignature.by_linked_system_id(solar_system_target_id)

        filtered_signatures =
          signatures
          |> Enum.filter(fn s ->
            s.system_id == source_system.id
          end)

        # Collect eve_ids for audit logging
        deleted_eve_ids = Enum.map(filtered_signatures, & &1.eve_id)

        filtered_signatures
        |> Enum.each(fn s ->
          if not is_nil(s.temporary_name) && s.temporary_name == target_system.temporary_name do
            map_id
            |> WandererApp.Map.Server.update_system_temporary_name(%{
              solar_system_id: solar_system_target_id,
              temporary_name: nil
            })
          end

          map_id
          |> WandererApp.Map.Server.update_system_linked_sig_eve_id(%{
            solar_system_id: solar_system_target_id,
            linked_sig_eve_id: nil
          })

          s
          |> WandererApp.Api.MapSystemSignature.destroy!()
        end)

        # Audit log signatures deleted with connection
        if deleted_eve_ids != [] do
          WandererApp.User.ActivityTracker.track_map_event(:signatures_removed, %{
            character_id: main_character_id,
            user_id: current_user_id,
            map_id: map_id,
            solar_system_id: solar_system_source_id,
            signatures: deleted_eve_ids
          })
        end

        WandererApp.Map.Server.Impl.broadcast!(
          map_id,
          :signatures_updated,
          solar_system_source_id
        )
      end
    end

    WandererApp.User.ActivityTracker.track_map_event(:map_connection_removed, %{
      character_id: main_character_id,
      user_id: current_user_id,
      map_id: map_id,
      solar_system_source_id: solar_system_source_id,
      solar_system_target_id: solar_system_target_id
    })

    {:noreply, socket}
  end

  def handle_ui_event(
        "update_connection_" <> param,
        %{
          "source" => solar_system_source_id,
          "target" => solar_system_target_id,
          "value" => value
        } = _event,
        %{
          assigns: %{
            map_id: map_id,
            current_user: %{id: current_user_id},
            main_character_id: main_character_id,
            has_tracked_characters?: true,
            user_permissions: %{update_system: true}
          }
        } =
          socket
      )
      when not is_nil(main_character_id) do
    method_atom =
      case param do
        "time_status" -> :update_connection_time_status
        "type" -> :update_connection_type
        "mass_status" -> :update_connection_mass_status
        "ship_size_type" -> :update_connection_ship_size_type
        "locked" -> :update_connection_locked
        "custom_info" -> :update_connection_custom_info
        _ -> nil
      end

    key_atom =
      case param do
        "time_status" -> :time_status
        "type" -> :type
        "mass_status" -> :mass_status
        "ship_size_type" -> :ship_size_type
        "locked" -> :locked
        "custom_info" -> :custom_info
        _ -> nil
      end

    solar_system_source_id_int = String.to_integer(solar_system_source_id)
    solar_system_target_id_int = String.to_integer(solar_system_target_id)

    WandererApp.User.ActivityTracker.track_map_event(:map_connection_updated, %{
      character_id: main_character_id,
      user_id: current_user_id,
      map_id: map_id,
      solar_system_source_id: solar_system_source_id_int,
      solar_system_target_id: solar_system_target_id_int,
      key: key_atom,
      value: value
    })

    apply(WandererApp.Map.Server, method_atom, [
      map_id,
      %{
        solar_system_source_id: solar_system_source_id_int,
        solar_system_target_id: solar_system_target_id_int
      }
      |> Map.put_new(key_atom, value)
      |> Map.put(:character_id, main_character_id)
    ])

    {:noreply, socket}
  end

  def handle_ui_event(
        "get_connection_info",
        %{"from" => from, "to" => to} = _event,
        %{assigns: %{map_id: map_id}} = socket
      ) do
    {:ok, info} = map_id |> get_connection_info(from, to)

    {:reply, info, socket}
  end

  def handle_ui_event(
        "get_passages",
        %{"from" => from, "to" => to} = _event,
        %{assigns: %{map_id: map_id}} = socket
      ) do
    {:ok, passages} = map_id |> get_connection_passages(from, to)

    {:reply, passages, socket}
  end

  def handle_ui_event(
        "update_passage_mass",
        %{"id" => passage_id, "mass" => mass} = event,
        %{
          assigns: %{
            map_id: map_id,
            has_tracked_characters?: true,
            current_user: current_user,
            user_permissions: user_permissions
          }
        } = socket
      ) do
    mass_value =
      cond do
        is_integer(mass) and mass > 0 ->
          mass

        is_binary(mass) ->
          case Integer.parse(mass) do
            {int_val, ""} when int_val > 0 -> int_val
            :error -> nil
            _ -> nil
          end

        true ->
          nil
      end

    mass_status =
      case Map.get(event, "mass_status") do
        status when status in [0, 1, 2] ->
          status

        status when is_binary(status) ->
          if status in ["0", "1", "2"], do: String.to_integer(status)

        _ ->
          nil
      end

    connection_closed = Map.get(event, "connection_closed") == true

    case WandererAppWeb.HandlerAuth.authorize_passage(passage_id, map_id) do
      {:ok, passage} ->
        owns_passage? =
          Enum.any?(current_user.characters, fn character ->
            "#{character.id}" == "#{passage.character_id}"
          end)

        if Map.get(user_permissions, :update_system, false) or owns_passage? do
          confirmation =
            if is_nil(mass_value) do
              %{mass_confirmed_at: nil, mass_confirmed_by_id: nil}
            else
              %{
                mass_confirmed_at: DateTime.utc_now(),
                mass_confirmed_by_id: current_user.id
              }
            end

          case WandererApp.Api.MapChainPassages.update_mass(
                 passage,
                 Map.put(confirmation, :mass, mass_value)
               ) do
            {:ok, _updated_passage} when not is_nil(mass_value) and connection_closed ->
              if latest_connection_passage?(map_id, passage) do
                WandererApp.Map.Server.close_connection(map_id, %{
                  solar_system_source_id: passage.solar_system_source_id,
                  solar_system_target_id: passage.solar_system_target_id,
                  character_id: passage.character_id,
                  user_id: current_user.id
                })
              end

            {:ok, _updated_passage}
            when not is_nil(mass_value) and not is_nil(mass_status) ->
              WandererApp.Map.Server.update_connection_mass_status(map_id, %{
                solar_system_source_id: passage.solar_system_source_id,
                solar_system_target_id: passage.solar_system_target_id,
                mass_status: mass_status
              })

            _ ->
              :ok
          end
        else
          Logger.warning(
            "update_passage_mass rejected: user does not own passage #{inspect(passage_id)}"
          )
        end

      {:error, :not_found} ->
        Logger.warning(
          "update_passage_mass rejected: passage #{inspect(passage_id)} not on map #{map_id}"
        )
    end

    {:noreply, socket}
  end

  def handle_ui_event(event, body, socket),
    do: MapCoreEventHandler.handle_ui_event(event, body, socket)

  defp latest_connection_passage?(map_id, passage) do
    case WandererApp.MapChainPassagesRepo.by_connection(
           map_id,
           passage.solar_system_source_id,
           passage.solar_system_target_id
         ) do
      {:ok, passages} when passages != [] ->
        passages
        |> Enum.max_by(&DateTime.to_unix(&1.inserted_at, :microsecond))
        |> Map.get(:id) == passage.id

      _ ->
        false
    end
  end

  defp get_connection_passages(map_id, from, to) do
    {:ok, passages} = WandererApp.MapChainPassagesRepo.by_connection(map_id, from, to)

    passages =
      passages
      |> Enum.map(fn p ->
        %{
          p
          | character: p.character |> MapEventHandler.map_ui_character_stat()
        }
        |> Map.put_new(
          :ship,
          WandererApp.Character.get_ship(%{ship: p.ship_type_id, ship_name: p.ship_name})
        )
        |> Map.drop([:ship_type_id, :ship_name])
      end)

    {:ok, %{passages: passages}}
  end

  defp get_connection_info(map_id, from, to) do
    map_id
    |> WandererApp.Map.Server.get_connection_info(%{
      solar_system_source_id: String.to_integer(from),
      solar_system_target_id: String.to_integer(to)
    })
    |> case do
      {:ok, info} ->
        {:ok, info}

      _ ->
        {:ok, %{}}
    end
  end
end
