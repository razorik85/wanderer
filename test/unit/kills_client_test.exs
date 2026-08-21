defmodule WandererApp.Kills.ClientTest do
  use ExUnit.Case, async: true

  alias WandererApp.Kills.Client

  test "health reconnect stops the previous WebSocket process" do
    {:ok, socket_pid} = Agent.start_link(fn -> :connected end)
    monitor_ref = Process.monitor(socket_pid)

    state = %Client{
      connected: true,
      connecting: false,
      socket_pid: socket_pid,
      last_message_time: System.system_time(:millisecond) - :timer.minutes(16)
    }

    assert {:noreply, new_state} = Client.handle_info(:health_check, state)

    refute new_state.connected
    refute new_state.connecting
    assert is_nil(new_state.socket_pid)
    assert_receive {:DOWN, ^monitor_ref, :process, ^socket_pid, :normal}
    assert_receive {:disconnected, :health_check_failed}
  end
end
