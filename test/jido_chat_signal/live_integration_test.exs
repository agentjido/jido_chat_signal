defmodule Jido.Chat.Signal.LiveIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Signal.{Adapter, Transport.CliClient}

  @moduletag :live

  @run_live System.get_env("RUN_LIVE_SIGNAL_TESTS") in ["1", "true", "TRUE", "yes"]
  @target System.get_env("SIGNAL_TEST_RECIPIENT")
  @transport_mode System.get_env("SIGNAL_TRANSPORT") || "cli"

  if @run_live and @target not in [nil, ""] do
    test "sends a live Signal message through the configured signal-cli transport" do
      text = "jido signal live #{System.system_time(:millisecond)}"
      account = System.get_env("SIGNAL_ACCOUNT")

      opts =
        [
          account: account
        ]
        |> transport_opts()

      assert {:ok, response} = Adapter.send_message(@target, text, opts)
      assert response.external_message_id

      file_path = live_attachment_path(text)
      on_exit(fn -> File.rm(file_path) end)

      assert {:ok, media_response} =
               Adapter.send_file(
                 @target,
                 %{path: file_path, filename: Path.basename(file_path)},
                 Keyword.put(opts, :caption, text <> " attachment")
               )

      assert media_response.external_message_id

      assert {:ok, gif_response} =
               Adapter.send_file(
                 @target,
                 live_gif(),
                 Keyword.put(opts, :caption, text <> " gif")
               )

      assert gif_response.external_message_id

      if account not in [nil, ""] do
        assert {:ok, quote_response} =
                 Adapter.send_message(
                   @target,
                   text <> " quote",
                   opts ++
                     [
                       reply_to_id: response.external_message_id,
                       quote_author: account,
                       quote_message: text
                     ]
                 )

        assert quote_response.external_message_id
      end
    end
  else
    test "live Signal tests require RUN_LIVE_SIGNAL_TESTS and SIGNAL_TEST_RECIPIENT" do
      refute @run_live and @target not in [nil, ""]
    end
  end

  defp transport_opts(opts) do
    case String.downcase(@transport_mode) do
      "cli" ->
        Keyword.put(opts, :transport, CliClient)

      _json_rpc ->
        Keyword.put(opts, :endpoint, System.get_env("SIGNAL_RPC_ENDPOINT"))
    end
  end

  defp live_attachment_path(text) do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_signal_live_#{System.unique_integer([:positive])}.txt"
      )

    File.write!(path, text <> "\n")
    path
  end

  defp live_gif do
    %{
      kind: :image,
      data: "R0lGODlhCgAKAIAAAP8AAAAAACH5BAAAAAAALAAAAAAKAAoAAAIIhI+py+0PYysAOw==",
      filename: "jido-signal-live.gif",
      media_type: "image/gif"
    }
  end
end
