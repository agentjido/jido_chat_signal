defmodule Jido.Chat.Signal.Adapter do
  @moduledoc "Signal `Jido.Chat.Adapter` implementation backed by `signal-cli`."
  use Jido.Chat.Adapter

  alias Jido.Chat.{Author, Incoming, Response}
  alias Jido.Chat.Signal.Transport.JsonRpcClient

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
      send_file: :fallback,
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
    {:ok, incoming_from_envelope(envelope, payload)}
  end

  def transform_incoming(%{"params" => %{"result" => %{"envelope" => envelope}}} = payload) do
    {:ok, incoming_from_envelope(envelope, payload)}
  end

  def transform_incoming(_), do: {:error, :unsupported_payload}

  @impl true
  def send_message(room_id, text, opts \\ []) do
    with {:ok, raw} <- transport(opts).send_message(to_string(room_id), text, opts) do
      {:ok,
       Response.new(%{
         external_message_id: raw["timestamp"] || raw[:timestamp],
         external_room_id: room_id,
         timestamp: raw["timestamp"] || raw[:timestamp],
         channel_type: :signal,
         raw: raw
       })}
    end
  end

  @impl true
  def listener_child_specs(_bridge_id, _opts), do: {:error, :listener_not_implemented_yet}

  defp incoming_from_envelope(envelope, payload) do
    data = envelope["dataMessage"] || get_in(envelope, ["syncMessage", "sentMessage"]) || %{}
    group_id = get_in(data, ["groupInfo", "groupId"]) || get_in(data, ["groupV2", "masterKey"])
    source = envelope["sourceUuid"] || envelope["sourceNumber"] || envelope["source"]
    room_id = if group_id, do: "group:#{group_id}", else: source

    Incoming.new(%{
      external_room_id: room_id,
      external_thread_id: group_id,
      external_message_id: to_string(data["timestamp"] || envelope["timestamp"]),
      external_user_id: source,
      text: data["message"] || "",
      timestamp: data["timestamp"] || envelope["timestamp"],
      author: author(source, envelope["sourceName"]),
      chat_type: if(group_id, do: :group, else: :direct_message),
      raw: payload,
      metadata: %{"source_device" => envelope["sourceDevice"]}
    })
  end

  defp author(nil, _name), do: nil

  defp author(source, name) do
    Author.new(%{
      user_id: to_string(source),
      user_name: name || to_string(source),
      full_name: name
    })
  end

  defp transport(opts), do: Keyword.get(opts, :transport, JsonRpcClient)
end
