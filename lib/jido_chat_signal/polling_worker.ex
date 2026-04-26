defmodule Jido.Chat.Signal.PollingWorker do
  @moduledoc """
  Bridge-ingress polling worker for Signal receive transports.

  The worker drains pending Signal envelopes through a receiver module and emits
  raw payloads via `sink_mfa` so host runtimes can route them through ingress.
  """

  use GenServer

  alias Jido.Chat.Signal.Transport.CliClient

  @type sink_mfa :: {module(), atom(), [term()]}

  @type state :: %{
          bridge_id: String.t(),
          sink_mfa: sink_mfa(),
          sink_opts: keyword(),
          receiver: module(),
          receiver_opts: keyword(),
          poll_interval_ms: pos_integer(),
          max_backoff_ms: pos_integer(),
          backoff_ms: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    bridge_id = Keyword.fetch!(opts, :bridge_id)
    sink_mfa = Keyword.fetch!(opts, :sink_mfa)
    poll_interval_ms = normalize_pos_integer(opts[:poll_interval_ms], 1_000)

    state = %{
      bridge_id: bridge_id,
      sink_mfa: sink_mfa,
      sink_opts: Keyword.get(opts, :sink_opts, []),
      receiver: Keyword.get(opts, :receiver, CliClient),
      receiver_opts: Keyword.get(opts, :receiver_opts, []),
      poll_interval_ms: poll_interval_ms,
      max_backoff_ms: normalize_pos_integer(opts[:max_backoff_ms], 10_000),
      backoff_ms: poll_interval_ms
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    case state.receiver.receive_messages(state.receiver_opts) do
      {:ok, messages} when is_list(messages) ->
        case emit_messages(messages, state) do
          :ok ->
            schedule_poll(state.poll_interval_ms)
            {:noreply, %{state | backoff_ms: state.poll_interval_ms}}

          {:error, _reason} ->
            schedule_backoff(state)
        end

      {:ok, _invalid} ->
        schedule_backoff(state)

      {:error, _reason} ->
        schedule_backoff(state)
    end
  end

  defp emit_messages(messages, state) do
    messages
    |> Enum.reduce([], fn message, errors ->
      case emit_message(state, message) do
        :ok -> errors
        {:error, reason} -> [reason | errors]
      end
    end)
    |> case do
      [] -> :ok
      errors -> {:error, {:sink_failures, Enum.reverse(errors)}}
    end
  end

  defp emit_message(state, message) when is_map(message) do
    case invoke_sink(state.sink_mfa, message, state.sink_opts) do
      {:ok, _result} -> :ok
      :ok -> :ok
      {:error, _reason} = error -> error
      other -> {:error, {:invalid_sink_result, other}}
    end
  end

  defp emit_message(_state, _message), do: {:error, :invalid_message_payload}

  defp invoke_sink({module, function, base_args}, payload, opts)
       when is_atom(module) and is_atom(function) and is_list(base_args) and is_list(opts) do
    apply(module, function, base_args ++ [payload, Keyword.put(opts, :mode, :payload)])
  end

  defp invoke_sink(_sink_mfa, _payload, _opts), do: {:error, :invalid_sink_mfa}

  defp schedule_backoff(state) do
    delay = min(state.backoff_ms, state.max_backoff_ms)
    schedule_poll(delay)

    {:noreply,
     %{state | backoff_ms: min(max(delay * 2, state.poll_interval_ms), state.max_backoff_ms)}}
  end

  defp schedule_poll(delay_ms) when is_integer(delay_ms) and delay_ms >= 0 do
    Process.send_after(self(), :poll, delay_ms)
  end

  defp normalize_pos_integer(value, default)
  defp normalize_pos_integer(nil, default), do: default
  defp normalize_pos_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_pos_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp normalize_pos_integer(_value, default), do: default
end
