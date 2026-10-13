defmodule Jido.Chat.Signal.Normalizer do
  @moduledoc false

  alias Jido.Chat.{Delivery, MediaType}
  alias Jido.Chat.Signal.{Identity, MessageReceived, NormalizationFailed}
  alias Jido.Signal.Trace

  @spec normalize(Jido.Chat.Binding.t(), term()) ::
          {:ok, Delivery.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def normalize(binding, payload) do
    items = if is_list(payload), do: payload, else: [payload]
    delivery_id = "signal:" <> digest({binding.id, Enum.map(items, &provider_identity/1)})
    tracker = make_ref()
    Process.put(tracker, [])

    result =
      with {:ok, signals} <- facts(binding, delivery_id, items, tracker),
           do: Delivery.new(binding, delivery_id, signals)

    if match?({:error, _}, result), do: cancel(binding, Process.get(tracker))
    Process.delete(tracker)
    result
  end

  defp facts(binding, delivery_id, items, tracker) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      existing = Process.get(tracker)

      result =
        try do
          fact(binding, delivery_id, item, index, tracker)
        rescue
          _ -> :invalid
        catch
          _, _ -> :invalid
        end

      case result do
        {:ok, fact} ->
          {:cont, {:ok, acc ++ [fact]}}

        {:error, %Jido.Chat.Errors.Contract{code: code}} = error
        when code in [
               :signal_too_large,
               :delivery_too_large,
               :too_many_signals,
               :too_many_failures
             ] ->
          {:halt, error}

        _ ->
          cancel(binding, Process.get(tracker) -- existing)

          failure =
            NormalizationFailed.new!(
              %{
                "item_id" => item_identity(item),
                "delivery_id" => delivery_id,
                "code" => "invalid_item",
                "item_index" => index
              },
              options(binding, nil)
            )

          {:cont, {:ok, acc ++ [failure]}}
      end
    end)
  end

  defp item_identity(item), do: "signal:item:" <> digest({provider_identity(item), :message, 0})
  defp cancel(binding, refs), do: Enum.each(refs, &Jido.Chat.cancel_resource(binding, &1))

  defp fact(binding, delivery_id, item, _index, tracker) do
    item_id = item_identity(item)

    with {:ok, envelope} <- envelope(item),
         {:ok, data} <- data_message(envelope),
         {:ok, fields} <- message_fields(binding, envelope, data, tracker),
         fields <- Map.merge(fields, %{"item_id" => item_id, "delivery_id" => delivery_id}),
         {:ok, signal} <- MessageReceived.new(fields, options(binding, fields["room_id"])) do
      {:ok, signal}
    else
      result -> result
    end
  end

  defp envelope(%{"envelope" => envelope}) when is_map(envelope), do: {:ok, envelope}

  defp envelope(%{"params" => %{"envelope" => envelope}}) when is_map(envelope),
    do: {:ok, envelope}

  defp envelope(%{"params" => %{"result" => %{"envelope" => envelope}}}) when is_map(envelope),
    do: {:ok, envelope}

  defp envelope(_), do: :invalid

  defp data_message(envelope) do
    data = envelope["dataMessage"] || nested(envelope["syncMessage"], "sentMessage")
    if is_map(data), do: {:ok, data}, else: :invalid
  end

  defp message_fields(binding, envelope, data, tracker) do
    with {:ok, source, room, group, stamp} <- message_identity(envelope, data),
         {:ok, text, attachments} <- message_content(data),
         {:ok, media} <- media(binding, attachments, tracker) do
      sender = put_text(%{"id" => source}, "display_name", envelope["sourceName"])

      sender =
        if is_map(nested(envelope["syncMessage"], "sentMessage")),
          do: Map.put(sender, "is_self", true),
          else: sender

      fields = %{
        "room_id" => room,
        "message_id" => to_string(stamp),
        "sender" => sender,
        "text" => text,
        "conversation_kind" => if(is_binary(group), do: "group", else: "direct")
      }

      fields = if media == [], do: fields, else: Map.put(fields, "media", media)
      fields = if is_binary(group), do: Map.put(fields, "thread_id", group), else: fields
      fields = put_text(fields, "reply_to_id", quote_id(data["quote"]))
      {:ok, put_text(fields, "timestamp", timestamp(stamp))}
    else
      _ -> :invalid
    end
  end

  defp message_identity(envelope, data) do
    source = envelope["sourceUuid"] || envelope["sourceNumber"] || envelope["source"]
    group = group_id(data)
    room = conversation(envelope, data, group, source)
    stamp = data["timestamp"] || envelope["timestamp"]

    if non_empty_string?(source) and non_empty_string?(room) and valid_stamp?(stamp),
      do: {:ok, source, room, group, stamp},
      else: :invalid
  end

  defp message_content(data) do
    text = data["message"] || ""
    attachments = data["attachments"] || []

    if is_binary(text) and is_list(attachments) and (String.trim(text) != "" or attachments != []),
      do: {:ok, text, attachments},
      else: :invalid
  end

  defp conversation(_envelope, _data, group, _source) when is_binary(group) and group != "",
    do: "group:" <> group

  defp conversation(envelope, data, _group, source) do
    cond do
      Map.has_key?(data, "groupV2") ->
        nil

      is_map(nested(envelope["syncMessage"], "sentMessage")) ->
        data["destinationUuid"] || data["destinationNumber"] || data["destination"]

      true ->
        source
    end
  end

  defp group_id(data), do: nested(data["groupInfo"], "groupId")

  defp nested(map, key) when is_map(map), do: map[key]
  defp nested(_map, _key), do: nil
  defp non_empty_string?(value), do: is_binary(value) and value != ""
  defp valid_stamp?(value) when is_integer(value), do: true
  defp valid_stamp?(value), do: non_empty_string?(value)

  defp media(binding, attachments, tracker) do
    Enum.reduce_while(attachments, {:ok, []}, fn
      attachment, {:ok, acc} when is_map(attachment) ->
        media_type = MediaType.normalize(non_blank(attachment, ["contentType", "content_type"]))
        name = non_blank(attachment, ["filename", "fileName"])

        case Jido.Chat.put_resource(binding, "media", attachment) do
          {:ok, ref} ->
            Process.put(tracker, [ref | Process.get(tracker)])

            value = %{
              "kind" => Atom.to_string(MediaType.kind(media_type, name)),
              "resource_ref" => ref
            }

            value = value |> put_text("media_type", media_type) |> put_text("name", name)
            {:cont, {:ok, [value | acc]}}

          error ->
            {:halt, error}
        end

      _, _ ->
        {:halt, :invalid}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      other -> other
    end
  end

  defp provider_identity(item) do
    with {:ok, envelope} <- envelope(item), {:ok, data} <- data_message(envelope) do
      source = envelope["sourceUuid"] || envelope["sourceNumber"] || envelope["source"]
      stamp = data["timestamp"] || envelope["timestamp"]
      room = conversation(envelope, data, group_id(data), source)

      if non_empty_string?(source) and non_empty_string?(room) and valid_stamp?(stamp),
        do: {source, room, stamp},
        else: digest(item)
    else
      _ -> digest(item)
    end
  end

  defp digest(value),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))
      |> Base.url_encode64(padding: false)

  defp quote_id(value) when is_map(value),
    do: value["id"] || value["timestamp"] || value["quoteTimestamp"]

  defp quote_id(_), do: nil

  defp timestamp(value) when is_integer(value) do
    case DateTime.from_unix(value, :millisecond) do
      {:ok, date} -> DateTime.to_iso8601(date)
      _ -> nil
    end
  end

  defp timestamp(_), do: nil

  defp non_blank(map, keys), do: Enum.find_value(keys, &non_blank_value(map[&1]))
  defp non_blank_value(value) when is_binary(value), do: if(String.trim(value) != "", do: value)
  defp non_blank_value(_value), do: nil

  defp put_text(map, _key, nil), do: map
  defp put_text(map, key, value) when is_integer(value), do: Map.put(map, key, to_string(value))
  defp put_text(map, key, value) when is_binary(value), do: Map.put(map, key, value)
  defp put_text(map, _key, _value), do: map

  defp options(binding, room) do
    subject = if is_binary(room), do: Identity.conversation_subject(binding.id, room)

    [
      source: binding.source,
      subject: subject,
      extensions: %{"traceparent" => Trace.to_traceparent(Trace.new())}
    ]
  end
end
