defmodule WandererApp.Map.ConnectionHistoryStats do
  @moduledoc false

  import Ecto.Query

  alias WandererApp.Api.{MapChainPassages, MapConnectionHistory, MapSolarSystem}
  alias WandererApp.Repo

  @period_days %{"7D" => 7, "30D" => 30, "90D" => 90}
  @default_period "30D"
  @supported_periods Map.keys(@period_days) ++ ["ALL"]

  def periods, do: ["7D", "30D", "90D", "ALL"]

  def normalize_period(period) when period in @supported_periods, do: period
  def normalize_period(_period), do: @default_period

  def get(map_id, period \\ @default_period) do
    period = normalize_period(period)
    histories = scoped_histories(map_id, period)
    passage_counts = passage_counts_query()

    summary =
      Repo.one(
        from(h in histories,
          select: %{
            connections: count(h.id),
            active: fragment("COUNT(*) FILTER (WHERE ? IS NULL)", h.closed_at),
            closed: fragment("COUNT(*) FILTER (WHERE ? IS NOT NULL)", h.closed_at),
            collapsed: fragment("COUNT(*) FILTER (WHERE ? = 'collapsed')", h.closure_reason),
            distinct_destinations: count(h.solar_system_target, :distinct),
            reduced: fragment("COUNT(*) FILTER (WHERE ? IS NOT NULL)", h.reduced_at),
            critical: fragment("COUNT(*) FILTER (WHERE ? IS NOT NULL)", h.critical_at),
            average_lifetime_seconds:
              fragment(
                "COALESCE(AVG(EXTRACT(EPOCH FROM (? - ?))) FILTER (WHERE ? IS NOT NULL), 0)",
                h.closed_at,
                h.opened_at,
                h.closed_at
              )
          }
        )
      )

    passage_count =
      Repo.one(
        from(p in MapChainPassages,
          join: h in subquery(from(h in histories, select: %{id: h.id})),
          on: h.id == p.connection_history_id,
          select: count(p.id)
        )
      )

    %{
      period: period,
      summary:
        summary
        |> Map.put(:passages, passage_count)
        |> normalize_numbers(),
      destinations: top_destinations(histories, passage_counts),
      routes: top_routes(histories, passage_counts),
      wormhole_types: wormhole_types(histories),
      closure_reasons: closure_reasons(histories)
    }
  end

  defp scoped_histories(map_id, period) do
    query =
      from(h in MapConnectionHistory,
        where: h.map_id == ^map_id and h.type == 0
      )

    case Map.get(@period_days, period) do
      nil ->
        query

      days ->
        cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
        from(h in query, where: h.opened_at >= ^cutoff)
    end
  end

  defp passage_counts_query do
    from(p in MapChainPassages,
      where: not is_nil(p.connection_history_id),
      group_by: p.connection_history_id,
      select: %{
        connection_history_id: p.connection_history_id,
        passages: count(p.id)
      }
    )
  end

  defp top_destinations(histories, passage_counts) do
    Repo.all(
      from(h in histories,
        left_join: passage_count in subquery(passage_counts),
        on: passage_count.connection_history_id == h.id,
        left_join: system in MapSolarSystem,
        on: system.solar_system_id == h.solar_system_target,
        group_by: [
          h.solar_system_target,
          system.solar_system_name,
          system.security,
          system.class_title
        ],
        order_by: [desc: count(h.id), desc: max(h.opened_at)],
        limit: 10,
        select: %{
          solar_system_id: h.solar_system_target,
          name: system.solar_system_name,
          security: system.security,
          class_title: system.class_title,
          connections: count(h.id),
          passages: fragment("COALESCE(SUM(?), 0)", passage_count.passages),
          last_seen_at: max(h.opened_at)
        }
      )
    )
    |> Enum.map(&normalize_numbers/1)
  end

  defp top_routes(histories, passage_counts) do
    Repo.all(
      from(h in histories,
        left_join: passage_count in subquery(passage_counts),
        on: passage_count.connection_history_id == h.id,
        left_join: source_system in MapSolarSystem,
        on: source_system.solar_system_id == h.solar_system_source,
        left_join: target_system in MapSolarSystem,
        on: target_system.solar_system_id == h.solar_system_target,
        group_by: [
          h.solar_system_source,
          h.solar_system_target,
          source_system.solar_system_name,
          target_system.solar_system_name
        ],
        order_by: [desc: count(h.id), desc: max(h.opened_at)],
        limit: 10,
        select: %{
          source_id: h.solar_system_source,
          source_name: source_system.solar_system_name,
          target_id: h.solar_system_target,
          target_name: target_system.solar_system_name,
          connections: count(h.id),
          passages: fragment("COALESCE(SUM(?), 0)", passage_count.passages),
          average_lifetime_seconds:
            fragment(
              "COALESCE(AVG(EXTRACT(EPOCH FROM (? - ?))) FILTER (WHERE ? IS NOT NULL), 0)",
              h.closed_at,
              h.opened_at,
              h.closed_at
            ),
          last_seen_at: max(h.opened_at)
        }
      )
    )
    |> Enum.map(&normalize_numbers/1)
  end

  defp wormhole_types(histories) do
    Repo.all(
      from(h in histories,
        group_by: h.wormhole_type,
        order_by: [desc: count(h.id)],
        limit: 10,
        select: %{name: h.wormhole_type, count: count(h.id)}
      )
    )
    |> Enum.map(&normalize_numbers/1)
  end

  defp closure_reasons(histories) do
    Repo.all(
      from(h in histories,
        where: not is_nil(h.closed_at),
        group_by: h.closure_reason,
        order_by: [desc: count(h.id)],
        select: %{reason: h.closure_reason, count: count(h.id)}
      )
    )
    |> Enum.map(&normalize_numbers/1)
  end

  defp normalize_numbers(values) do
    Map.new(values, fn
      {key, %Decimal{} = value} when key in [:average_lifetime_seconds] ->
        {key, Decimal.to_float(value)}

      {key, %Decimal{} = value} ->
        {key, Decimal.to_integer(value)}

      pair ->
        pair
    end)
  end
end
