defmodule Jido.Chat.Signal.LiveIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :live

  @run_live System.get_env("RUN_LIVE_SIGNAL_TESTS") in ["1", "true", "TRUE", "yes"]
  @target System.get_env("SIGNAL_TEST_RECIPIENT")

  if @run_live and @target not in [nil, ""] do
    test "sends a live Signal message through signal-cli JSON-RPC" do
      text = "jido signal live #{System.system_time(:millisecond)}"

      opts = [
        endpoint: System.get_env("SIGNAL_RPC_ENDPOINT"),
        account: System.get_env("SIGNAL_ACCOUNT")
      ]

      assert {:ok, response} = Jido.Chat.Signal.Adapter.send_message(@target, text, opts)
      assert response.external_message_id
    end
  else
    test "live Signal tests require RUN_LIVE_SIGNAL_TESTS and SIGNAL_TEST_RECIPIENT" do
      refute @run_live and @target not in [nil, ""]
    end
  end
end
