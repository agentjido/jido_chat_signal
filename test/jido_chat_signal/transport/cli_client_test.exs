defmodule Jido.Chat.Signal.Transport.CliClientTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.FileUpload
  alias Jido.Chat.Signal.Transport.CliClient

  test "builds signal-cli attachment and quote arguments" do
    tmp_dir = System.tmp_dir!()
    args_path = Path.join(tmp_dir, "jido_signal_cli_args_#{System.unique_integer([:positive])}")
    executable = Path.join(tmp_dir, "jido_signal_cli_#{System.unique_integer([:positive])}.sh")

    File.write!(executable, """
    #!/bin/sh
    printf '%s\\n' "$@" > "$SIGNAL_CLI_TEST_ARGS"
    echo 1776000001
    """)

    File.chmod!(executable, 0o755)

    previous_args_path = System.get_env("SIGNAL_CLI_TEST_ARGS")
    System.put_env("SIGNAL_CLI_TEST_ARGS", args_path)

    on_exit(fn ->
      File.rm(executable)
      File.rm(args_path)

      if previous_args_path do
        System.put_env("SIGNAL_CLI_TEST_ARGS", previous_args_path)
      else
        System.delete_env("SIGNAL_CLI_TEST_ARGS")
      end
    end)

    assert {:ok, response} =
             CliClient.send_message("+15555550100", "reply",
               executable: executable,
               account: "+15555550101",
               attachments: [%{path: "/tmp/report.txt"}],
               reply_to_id: "1775999999",
               quote_author: "+15555550100",
               quote_message: "parent"
             )

    assert response["timestamp"] == "1776000001"

    assert File.read!(args_path) |> String.split("\n", trim: true) == [
             "-a",
             "+15555550101",
             "send",
             "-a",
             "/tmp/report.txt",
             "--quote-timestamp",
             "1775999999",
             "--quote-author",
             "+15555550100",
             "--quote-message",
             "parent",
             "-m",
             "reply",
             "+15555550100"
           ]
  end

  test "accepts data-backed file upload structs as data URI attachments" do
    tmp_dir = System.tmp_dir!()

    args_path =
      Path.join(tmp_dir, "jido_signal_cli_data_args_#{System.unique_integer([:positive])}")

    executable =
      Path.join(tmp_dir, "jido_signal_cli_data_#{System.unique_integer([:positive])}.sh")

    File.write!(executable, """
    #!/bin/sh
    printf '%s\\n' "$@" > "$SIGNAL_CLI_TEST_ARGS"
    echo 1776000002
    """)

    File.chmod!(executable, 0o755)

    previous_args_path = System.get_env("SIGNAL_CLI_TEST_ARGS")
    System.put_env("SIGNAL_CLI_TEST_ARGS", args_path)

    on_exit(fn ->
      File.rm(executable)
      File.rm(args_path)

      if previous_args_path do
        System.put_env("SIGNAL_CLI_TEST_ARGS", previous_args_path)
      else
        System.delete_env("SIGNAL_CLI_TEST_ARGS")
      end
    end)

    attachment =
      FileUpload.new(%{
        kind: :image,
        data: "R0lGODlhAQABAAAAACw=",
        filename: "tiny.gif",
        media_type: "image/gif"
      })

    assert {:ok, _response} =
             CliClient.send_message("+15555550100", "gif",
               executable: executable,
               account: "",
               attachments: [attachment]
             )

    assert [
             "send",
             "-a",
             "data:image/gif;filename=tiny.gif;base64,R0lGODlhAQABAAAAACw=",
             "-m",
             "gif",
             "+15555550100"
           ] = File.read!(args_path) |> String.split("\n", trim: true)
  end

  test "rejects remote attachments because signal-cli needs local files or data URIs" do
    assert {:error, {:unsupported_remote_attachment, "https://example.test/file.txt"}} =
             CliClient.send_message("+15555550100", "file",
               executable: "/does/not/matter",
               attachments: [%{url: "https://example.test/file.txt"}]
             )
  end

  test "receives line-delimited json envelopes with polling arguments" do
    tmp_dir = System.tmp_dir!()

    args_path =
      Path.join(tmp_dir, "jido_signal_cli_receive_args_#{System.unique_integer([:positive])}")

    executable =
      Path.join(tmp_dir, "jido_signal_cli_receive_#{System.unique_integer([:positive])}.sh")

    File.write!(executable, """
    #!/bin/sh
    printf '%s\\n' "$@" > "$SIGNAL_CLI_TEST_ARGS"
    printf '%s\\n' 'INFO  AccountHelper - The Signal protocol expects that incoming messages are regularly received.'
    printf '%s\\n' '{"envelope":{"timestamp":1776000003}}'
    printf '%s\\n' '{"envelope":{"timestamp":1776000004}}'
    """)

    File.chmod!(executable, 0o755)

    previous_args_path = System.get_env("SIGNAL_CLI_TEST_ARGS")
    System.put_env("SIGNAL_CLI_TEST_ARGS", args_path)

    on_exit(fn ->
      File.rm(executable)
      File.rm(args_path)

      if previous_args_path do
        System.put_env("SIGNAL_CLI_TEST_ARGS", previous_args_path)
      else
        System.delete_env("SIGNAL_CLI_TEST_ARGS")
      end
    end)

    assert {:ok,
            [
              %{"envelope" => %{"timestamp" => 1_776_000_003}},
              %{"envelope" => %{"timestamp" => 1_776_000_004}}
            ]} =
             CliClient.receive_messages(
               executable: executable,
               account: "+15555550101",
               receive_timeout_s: 2,
               max_messages: 3,
               ignore_attachments: true
             )

    assert File.read!(args_path) |> String.split("\n", trim: true) == [
             "-a",
             "+15555550101",
             "-o",
             "json",
             "receive",
             "--timeout",
             "2",
             "--max-messages",
             "3",
             "--ignore-attachments"
           ]
  end
end
