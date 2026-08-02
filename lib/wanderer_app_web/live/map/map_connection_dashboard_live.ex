defmodule WandererAppWeb.MapConnectionDashboardLive do
  use WandererAppWeb, :live_view

  alias WandererApp.Map.ConnectionHistoryStats

  @impl true
  def mount(
        %{"slug" => map_slug},
        _session,
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case WandererApp.Maps.check_user_can_view_connections(map_slug, current_user) do
      {:ok, %{id: map_id, name: map_name}} ->
        {:ok,
         assign(socket,
           map_id: map_id,
           map_name: map_name,
           map_slug: map_slug,
           period: "30D",
           periods: ConnectionHistoryStats.periods(),
           active_page: :connection_statistics,
           page_title: "Map - Connection Analytics"
         )}

      _error ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have access to connection analytics for this map.")
         |> push_navigate(to: ~p"/maps")}
    end
  end

  @impl true
  def handle_params(params, _url, %{assigns: %{map_id: _map_id}} = socket) do
    period = ConnectionHistoryStats.normalize_period(Map.get(params, "period"))
    {:noreply, socket |> assign(:period, period) |> load_statistics()}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load_statistics(socket)}

  defp load_statistics(%{assigns: %{map_id: map_id, period: period}} = socket) do
    assign_async(socket, :statistics, fn ->
      {:ok, %{statistics: ConnectionHistoryStats.get(map_id, period)}}
    end)
  end

  defp format_number(nil), do: "0"

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end

  defp format_number(number), do: to_string(number)

  defp format_duration(nil), do: "—"
  defp format_duration(seconds) when seconds <= 0, do: "—"

  defp format_duration(seconds) do
    seconds = round(seconds)

    cond do
      seconds < 3_600 -> "#{max(div(seconds, 60), 1)} min"
      seconds < 172_800 -> "#{Float.round(seconds / 3_600, 1)} h"
      true -> "#{Float.round(seconds / 86_400, 1)} d"
    end
  end

  defp format_datetime(nil), do: "—"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%d.%m.%Y %H:%M")

  defp system_name(nil, solar_system_id), do: to_string(solar_system_id)
  defp system_name(name, _solar_system_id), do: name

  defp system_class(nil, nil), do: "Unknown"
  defp system_class(nil, security), do: security
  defp system_class(class_title, _security), do: class_title

  defp wormhole_type(nil), do: "Unknown"
  defp wormhole_type(""), do: "Unknown"
  defp wormhole_type(type), do: type

  defp closure_reason(nil), do: "Other / unknown"
  defp closure_reason("collapsed"), do: "Collapsed"
  defp closure_reason("manual"), do: "Removed manually"
  defp closure_reason("auto_cleanup"), do: "Automatic cleanup"
  defp closure_reason("signature_removed"), do: "Signature removed"
  defp closure_reason("system_removed"), do: "System removed"
  defp closure_reason("duplicate_replaced"), do: "Duplicate replaced"
  defp closure_reason("deleted"), do: "Deleted"
  defp closure_reason(reason), do: reason |> String.replace("_", " ") |> String.capitalize()

  defp percentage(_part, 0), do: "0%"
  defp percentage(part, total), do: "#{round(part / total * 100)}%"

  defp bar_width(_count, []), do: 0

  defp bar_width(count, rows) do
    max_count = rows |> Enum.map(& &1.count) |> Enum.max(fn -> 1 end)
    max(round(count / max_count * 100), 4)
  end
end
