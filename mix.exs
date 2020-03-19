defmodule Sunny.MixProject do
  use Mix.Project

  def project do
    [
      app: :qsb36,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/patrick7777776/QSB36"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 1.6"},
      {:jason, "~> 1.1"},
      {:earmark, "~> 1.2", only: :dev},
			{:ex_doc, "~> 0.19", only: :dev}
    ]
  end

  defp description() do
    "Query SunnyBoy 3.6 inverter for current output in watts, total yield and other information via the inverter's internal web interface."
  end

  defp package() do
    [
      name: "qsb36",
      licenses: ["AGPL-3.0"],
      links: %{"GitHub" => "https://github.com/patrick7777776/QSB36"}
    ]
  end

end
