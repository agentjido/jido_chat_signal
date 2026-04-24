defmodule Jido.Chat.Signal.Transport.JsonRpcClient do
  @moduledoc "HTTP JSON-RPC transport for `signal-cli daemon --http`."
  @behaviour Jido.Chat.Signal.Transport

  @impl true
  def send_message(target, text, opts) do
    params =
      if String.starts_with?(to_string(target), "group:") do
        %{"groupId" => String.replace_prefix(to_string(target), "group:", ""), "message" => text}
      else
        %{"recipient" => [to_string(target)], "message" => text}
      end
      |> maybe_put_account(opts)

    rpc("send", params, opts)
  end

  @impl true
  def list_groups(opts) do
    with {:ok, result} <- rpc("listGroups", maybe_put_account(%{}, opts), opts) do
      {:ok, result}
    end
  end

  defp rpc(method, params, opts) do
    endpoint =
      Keyword.get(opts, :endpoint) || System.get_env("SIGNAL_RPC_ENDPOINT") ||
        "http://127.0.0.1:8080/api/v1/rpc"

    id = System.unique_integer([:positive]) |> to_string()
    body = %{"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => id}

    case Req.post(endpoint, json: body) do
      {:ok, %{status: status, body: %{"result" => result}}} when status in 200..299 ->
        {:ok, result}

      {:ok, %{status: status, body: %{"error" => error}}} ->
        {:error, {:signal_rpc_error, status, error}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:signal_rpc_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_account(params, opts) do
    account = Keyword.get(opts, :account) || System.get_env("SIGNAL_ACCOUNT")
    if account in [nil, ""], do: params, else: Map.put(params, "account", account)
  end
end
