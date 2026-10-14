defmodule Jido.Chat.Signal.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/agentjido/jido_chat_signal"
  @description "Signal adapter package for Jido.Chat using signal-cli"

  def project do
    [
      app: :jido_chat_signal,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Jido Chat Signal",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  def cli, do: [preferred_envs: [quality: :test, q: :test]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      chat_dependency(),
      signal_test_dependency(),
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:dotenvy, "~> 1.1", only: [:test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  # The published beta lacks the Signal API used by this migration.
  defp signal_test_dependency do
    {:jido_signal,
     git: "https://github.com/agentjido/jido_signal.git",
     ref: "d6611eca1c95eb507843baceb55991e4801d8421",
     only: [:dev, :test],
     override: true}
  end

  defp chat_dependency do
    case {Mix.env(), System.get_env("JIDO_CHAT_PATH")} do
      {env, path} when env in [:dev, :test] and is_binary(path) and path != "" ->
        {:jido_chat, path: path}

      {env, _} when env in [:dev, :test] ->
        {:jido_chat,
         git: "https://github.com/agentjido/jido_chat.git",
         ref: "2a9c21a860cb8c5f1069a865a981a8be035f56c0",
         override: true}

      _ ->
        {:jido_chat, "~> 2.0"}
    end
  end

  defp aliases do
    [
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test"
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md", "usage-rules.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://github.com/agentjido/jido_chat_signal/blob/main/CHANGELOG.md",
        "Discord" => "https://jido.run/discord",
        "Documentation" => "https://hexdocs.pm/jido_chat_signal",
        "GitHub" => @source_url,
        "Website" => "https://jido.run"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "usage-rules.md"
      ]
    ]
  end
end
