defmodule WandererApp.Map.Server.MassTrackingLifecycleTest do
  use ExUnit.Case, async: true

  alias WandererApp.Map.Server.ConnectionsImpl

  test "keeps the current lifecycle when a signature side is learned for the first time" do
    current_start = ~U[2026-07-19 10:00:00Z]
    now = ~U[2026-07-19 12:00:00Z]

    assert ConnectionsImpl.resolve_mass_tracking_started_at(
             nil,
             "ABC-123",
             current_start,
             now
           ) == current_start
  end

  test "does not reset when the same signature is linked again" do
    current_start = ~U[2026-07-19 10:00:00Z]
    now = ~U[2026-07-19 12:00:00Z]

    assert ConnectionsImpl.resolve_mass_tracking_started_at(
             "ABC-123",
             "ABC-123",
             current_start,
             now
           ) == current_start
  end

  test "starts a new lifecycle when a known side receives a new signature" do
    current_start = ~U[2026-07-19 10:00:00Z]
    now = ~U[2026-07-19 12:00:00Z]

    assert ConnectionsImpl.resolve_mass_tracking_started_at(
             "ABC-123",
             "XYZ-789",
             current_start,
             now
           ) == now
  end
end
