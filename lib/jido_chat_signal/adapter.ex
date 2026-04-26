defmodule Jido.Chat.Signal.Adapter do
  @moduledoc "Signal `Jido.Chat.Adapter` implementation backed by `signal-cli`."
  use Jido.Chat.Adapter

  alias Jido.Chat.{Author, FileUpload, Incoming, Media, PostPayload, Response}
  alias Jido.Chat.Signal.{PollingWorker, Transport.CliClient, Transport.JsonRpcClient}

  @no_listener_modes MapSet.new(["none", "manual"])
  @polling_modes MapSet.new([
                   "polling",
                   "receive",
                   "cli_polling",
                   "rpc_polling",
                   "json_rpc_polling",
                   "json_rpc_receive"
                 ])
  @rpc_polling_modes MapSet.new(["rpc_polling", "json_rpc_polling", "json_rpc_receive"])

  @impl true
  def channel_type, do: :signal

  @impl true
  def capabilities do
    %{
      send_message: :native,
      fetch_metadata: :fallback,
      webhook: :unsupported,
      verify_webhook: :unsupported,
      parse_event: :unsupported,
      send_file: :native,
      post_message: :native,
      edit_message: :unsupported,
      delete_message: :unsupported,
      start_typing: :unsupported,
      add_reaction: :unsupported,
      remove_reaction: :unsupported,
      post_ephemeral: :unsupported,
      open_modal: :unsupported
    }
  end

  @impl true
  def transform_incoming(%{"envelope" => envelope} = payload) do
    with {:ok, data} <- data_message(envelope) do
      {:ok, incoming_from_envelope(envelope, data, payload)}
    end
  end

  def transform_incoming(%{"params" => %{"result" => %{"envelope" => envelope}}} = payload) do
    with {:ok, data} <- data_message(envelope) do
      {:ok, incoming_from_envelope(envelope, data, payload)}
    end
  end

  def transform_incoming(_), do: {:error, :unsupported_payload}

  @impl true
  def send_message(room_id, text, opts \\ []) do
    with {:ok, raw} <- transport(opts).send_message(to_string(room_id), text, opts) do
      {:ok, response_from_raw(raw, room_id)}
    end
  end

  @impl true
  def send_file(room_id, file, opts \\ []) do
    payload =
      PostPayload.text(Keyword.get(opts, :caption, Keyword.get(opts, :text, "")),
        files: [FileUpload.normalize(file)]
      )

    post_message(room_id, payload, opts)
  end

  @impl true
  def post_message(room_id, %PostPayload{} = payload, opts \\ []) do
    attachments = Enum.map(PostPayload.upload_candidates(payload), &FileUpload.normalize/1)
    text = PostPayload.display_text(payload) || ""
    send_opts = opts |> Keyword.delete(:caption) |> Keyword.put(:attachments, attachments)

    with {:ok, raw} <- transport(opts).send_message(to_string(room_id), text, send_opts) do
      {:ok,
       raw
       |> response_from_raw(room_id)
       |> put_response_metadata(:attachments, PostPayload.outbound_attachments(payload))}
    end
  end

  @impl true
  def listener_child_specs(bridge_id, opts \\ []) when is_binary(bridge_id) and is_list(opts) do
    ingress = normalize_ingress_opts(opts)

    case ingress_mode(ingress) do
      :none ->
        {:ok, []}

      :polling ->
        with {:ok, sink_mfa} <- validate_sink_mfa(Keyword.get(opts, :sink_mfa)) do
          worker_opts = polling_worker_opts(bridge_id, ingress, opts, sink_mfa)

          {:ok,
           [
             Supervisor.child_spec(
               {PollingWorker, worker_opts},
               id: {:signal_polling_worker, bridge_id}
             )
           ]}
        end

      :invalid ->
        {:error, :invalid_ingress_mode}
    end
  end

  defp incoming_from_envelope(envelope, data, payload) do
    group_id = get_in(data, ["groupInfo", "groupId"]) || get_in(data, ["groupV2", "masterKey"])
    source = envelope["sourceUuid"] || envelope["sourceNumber"] || envelope["source"]
    room_id = if group_id, do: "group:#{group_id}", else: source

    Incoming.new(%{
      external_room_id: room_id,
      external_thread_id: group_id,
      external_message_id: to_string(data["timestamp"] || envelope["timestamp"]),
      external_reply_to_id: quote_id(data["quote"]),
      external_user_id: source,
      text: data["message"] || "",
      timestamp: data["timestamp"] || envelope["timestamp"],
      author: author(source, envelope["sourceName"]),
      chat_type: if(group_id, do: :group, else: :direct_message),
      media: media_from_attachments(data["attachments"]),
      raw: payload,
      metadata: %{
        "source_device" => envelope["sourceDevice"],
        "quote" => data["quote"]
      }
    })
  end

  defp data_message(envelope) when is_map(envelope) do
    data =
      cond do
        is_map(envelope["dataMessage"]) ->
          envelope["dataMessage"]

        is_map(get_in(envelope, ["syncMessage", "sentMessage"])) ->
          get_in(envelope, ["syncMessage", "sentMessage"])

        true ->
          nil
      end

    cond do
      is_nil(data) -> {:error, :unsupported_envelope}
      message_content?(data) -> {:ok, data}
      true -> {:error, :empty_data_message}
    end
  end

  defp data_message(_envelope), do: {:error, :unsupported_envelope}

  defp message_content?(data) when is_map(data) do
    non_empty_string?(data["message"]) or non_empty_attachments?(data["attachments"])
  end

  defp non_empty_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_empty_string?(_value), do: false

  defp non_empty_attachments?(attachments) when is_list(attachments), do: attachments != []
  defp non_empty_attachments?(_attachments), do: false

  defp author(nil, _name), do: nil

  defp author(source, name) do
    Author.new(%{
      user_id: to_string(source),
      user_name: name || to_string(source),
      full_name: name
    })
  end

  defp response_from_raw(raw, room_id) do
    Response.new(%{
      external_message_id: raw["timestamp"] || raw[:timestamp],
      external_room_id: room_id,
      timestamp: raw["timestamp"] || raw[:timestamp],
      channel_type: :signal,
      raw: raw
    })
  end

  defp put_response_metadata(%Response{} = response, key, value) do
    %{response | metadata: Map.put(response.metadata, key, value)}
  end

  defp quote_id(nil), do: nil

  defp quote_id(quote) when is_map(quote) do
    quote["id"] || quote["timestamp"] || quote["quoteTimestamp"]
  end

  defp media_from_attachments(attachments) when is_list(attachments) do
    Enum.map(attachments, fn attachment ->
      Media.new(%{
        media_type: attachment["contentType"] || attachment["content_type"],
        filename: attachment["filename"] || attachment["fileName"],
        size_bytes: attachment["size"],
        metadata: attachment
      })
    end)
  end

  defp media_from_attachments(_attachments), do: []

  defp transport(opts), do: Keyword.get(opts, :transport, JsonRpcClient)

  defp normalize_ingress_opts(opts) do
    opts
    |> Keyword.get(:ingress, %{})
    |> ensure_map()
  end

  defp ensure_map(%{} = map), do: map
  defp ensure_map(_), do: %{}

  defp ingress_mode(ingress) do
    mode = ingress |> map_get([:mode, "mode"]) |> normalize_mode()

    cond do
      is_nil(mode) -> :none
      MapSet.member?(@no_listener_modes, mode) -> :none
      MapSet.member?(@polling_modes, mode) -> :polling
      true -> :invalid
    end
  end

  defp validate_sink_mfa({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: {:ok, {module, function, args}}

  defp validate_sink_mfa(_), do: {:error, :invalid_sink_mfa}

  defp polling_worker_opts(bridge_id, ingress, opts, sink_mfa) do
    bridge_config = Keyword.get(opts, :bridge_config)
    credentials = bridge_credentials(bridge_config)

    [
      bridge_id: bridge_id,
      sink_mfa: sink_mfa,
      sink_opts: [bridge_id: bridge_id],
      receiver:
        Keyword.get(opts, :receiver) ||
          map_get(ingress, [:receiver, "receiver"]) ||
          default_polling_receiver(ingress),
      receiver_opts: receiver_opts(ingress, credentials),
      poll_interval_ms: map_get(ingress, [:poll_interval_ms, "poll_interval_ms"]) || 1_000,
      max_backoff_ms: map_get(ingress, [:max_backoff_ms, "max_backoff_ms"]) || 10_000
    ]
  end

  defp default_polling_receiver(ingress) do
    if ingress |> map_get([:mode, "mode"]) |> normalize_mode() |> rpc_polling_mode?(),
      do: JsonRpcClient,
      else: CliClient
  end

  defp normalize_mode(nil), do: nil
  defp normalize_mode(mode) when is_atom(mode), do: Atom.to_string(mode)
  defp normalize_mode(mode) when is_binary(mode), do: String.downcase(mode)
  defp normalize_mode(mode), do: mode |> to_string() |> String.downcase()

  defp rpc_polling_mode?(mode), do: MapSet.member?(@rpc_polling_modes, mode)

  defp receiver_opts(ingress, credentials) do
    ingress
    |> map_get([:receiver_opts, "receiver_opts"])
    |> keyword_opts()
    |> maybe_put_opt(
      :account,
      map_get(ingress, [:account, "account"]) || map_get(credentials, [:account, "account"])
    )
    |> maybe_put_opt(
      :endpoint,
      map_get(ingress, [:endpoint, "endpoint", :rpc_endpoint, "rpc_endpoint"])
    )
    |> maybe_put_opt(:executable, map_get(ingress, [:executable, "executable"]))
    |> maybe_put_opt(
      :config_path,
      map_get(ingress, [:config_path, "config_path", :config, "config"])
    )
    |> maybe_put_opt(
      :receive_timeout_s,
      map_get(ingress, [:receive_timeout_s, "receive_timeout_s", :timeout_s, "timeout_s"])
    )
    |> maybe_put_opt(:max_messages, map_get(ingress, [:max_messages, "max_messages"]))
    |> maybe_put_opt(
      :ignore_attachments,
      map_get(ingress, [:ignore_attachments, "ignore_attachments"])
    )
    |> maybe_put_opt(:ignore_stories, map_get(ingress, [:ignore_stories, "ignore_stories"]))
    |> maybe_put_opt(:ignore_avatars, map_get(ingress, [:ignore_avatars, "ignore_avatars"]))
    |> maybe_put_opt(:ignore_stickers, map_get(ingress, [:ignore_stickers, "ignore_stickers"]))
    |> maybe_put_opt(
      :send_read_receipts,
      map_get(ingress, [:send_read_receipts, "send_read_receipts"])
    )
  end

  defp keyword_opts(opts) when is_list(opts), do: opts
  defp keyword_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  defp keyword_opts(_opts), do: []

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp bridge_credentials(%{credentials: credentials}) when is_map(credentials), do: credentials
  defp bridge_credentials(_), do: %{}

  defp map_get(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp map_get(_map, _keys), do: nil
end
