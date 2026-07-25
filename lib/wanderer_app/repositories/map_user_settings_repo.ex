defmodule WandererApp.MapUserSettingsRepo do
  use WandererApp, :repository
  require Ash.Query

  @default_form_data %{
    "select_on_spash" => false,
    "link_signature_on_splash" => false,
    "delete_connection_with_sigs" => false,
    "primary_character_id" => nil,
    "bookmark_name_format" => "",
    "bookmark_custom_mapping" => %{},
    "system_auto_tag" => "",
    "system_custom_label_name" => "",
    "bookmark_return_hole_ignore" => false,
    "bookmark_return_hole_symbol" => "",
    "mass_tracking_enabled" => true,
    "mass_templates" => []
  }

  def get(map_id, user_id) do
    map_id
    |> WandererApp.Api.MapUserSettings.by_user_id(user_id)
    |> case do
      {:ok, settings} ->
        {:ok, settings}

      _ ->
        {:ok, nil}
    end
  end

  def get!(map_id, user_id) do
    WandererApp.Api.MapUserSettings.by_user_id(map_id, user_id)
    |> case do
      {:ok, user_settings} -> user_settings
      _ -> nil
    end
  end

  def create_or_update(map_id, user_id, nil) do
    create_or_update(map_id, user_id, @default_form_data |> Jason.encode!())
  end

  def create_or_update(map_id, user_id, settings) do
    get!(map_id, user_id)
    |> case do
      user_settings when not is_nil(user_settings) ->
        user_settings
        |> WandererApp.Api.MapUserSettings.update_settings(%{settings: settings})

      _ ->
        WandererApp.Api.MapUserSettings.create(%{
          map_id: map_id,
          user_id: user_id,
          settings: settings
        })
    end
  end

  def get_hubs(map_id, user_id) do
    case WandererApp.MapUserSettingsRepo.get(map_id, user_id) do
      {:ok, user_settings} when not is_nil(user_settings) ->
        {:ok, Map.get(user_settings, :hubs, [])}

      _ ->
        {:ok, []}
    end
  end

  def update_hubs(map_id, user_id, hubs) do
    get!(map_id, user_id)
    |> case do
      user_settings when not is_nil(user_settings) ->
        user_settings
        |> WandererApp.Api.MapUserSettings.update_hubs(%{hubs: hubs})

      _ ->
        WandererApp.Api.MapUserSettings.create!(%{
          map_id: map_id,
          user_id: user_id,
          settings: @default_form_data |> Jason.encode!()
        })
        |> WandererApp.Api.MapUserSettings.update_hubs(%{hubs: hubs})
    end
  end

  def to_form_data(nil), do: {:ok, @default_form_data}

  def to_form_data(%{settings: settings} = _user_settings),
    do: {:ok, Map.merge(@default_form_data, Jason.decode!(settings))}

  def to_form_data!(user_settings) do
    {:ok, data} = to_form_data(user_settings)
    data
  end

  def to_form_data_for_user(user_settings, user_id) do
    with {:ok, form_data} <- to_form_data(user_settings) do
      case Map.get(form_data, "mass_templates", []) do
        [_ | _] ->
          {:ok, form_data}

        _ ->
          {:ok, Map.put(form_data, "mass_templates", get_mass_templates_for_user(user_id))}
      end
    end
  end

  def sync_mass_templates_for_user(user_id, templates) when is_list(templates) do
    case list_by_user_id(user_id) do
      {:ok, settings_rows} ->
        Enum.reduce_while(settings_rows, :ok, fn settings_row, :ok ->
          settings =
            settings_row.settings
            |> decode_settings()
            |> Map.put("mass_templates", templates)
            |> Jason.encode!()

          case WandererApp.Api.MapUserSettings.update_settings(settings_row, %{settings: settings}) do
            {:ok, _} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_mass_templates_for_user(user_id) do
    case list_by_user_id(user_id) do
      {:ok, settings_rows} ->
        Enum.find_value(settings_rows, [], fn settings_row ->
          case Map.get(decode_settings(settings_row.settings), "mass_templates", []) do
            [_ | _] = templates -> templates
            _ -> nil
          end
        end)

      _ ->
        []
    end
  end

  defp list_by_user_id(user_id) do
    WandererApp.Api.MapUserSettings
    |> Ash.Query.new()
    |> Ash.Query.filter(user_id: user_id)
    |> Ash.read()
  end

  defp decode_settings(settings) when is_binary(settings) do
    case Jason.decode(settings) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp decode_settings(_), do: %{}

  def get_boolean_setting(settings, key, default \\ false) do
    settings
    |> Map.get(key, default)
    |> to_boolean()
  end

  def to_boolean(value) when is_binary(value), do: value |> String.to_existing_atom()
  def to_boolean(value) when is_boolean(value), do: value
end
