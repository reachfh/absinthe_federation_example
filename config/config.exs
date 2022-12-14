# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :absinthe_federation_example,
  ecto_repos: [AbsintheFederationExample.Repo]

# Configures the endpoint
config :absinthe_federation_example, AbsintheFederationExampleWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    view: AbsintheFederationExampleWeb.ErrorView,
    accepts: ~w(html json),
    layout: false
  ],
  pubsub_server: AbsintheFederationExample.PubSub,
  live_view: [signing_salt: "Dc3TFU7m"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :absinthe_federation_example, AbsintheFederationExample.Mailer,
  adapter: Swoosh.Adapters.Local

# Swoosh API client is needed for adapters other than SMTP.
config :swoosh, :api_client, false

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.29",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :logger,
  level: :info,
  utc_log: true

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id, :span_id]

if System.get_env("RELEASE_MODE") do
  config :kernel, :logger, [
    {:handler, :default, :logger_std_h,
     %{
       formatter:
         {:logger_formatter_json,
          %{
            names: :datadog,
            template: [
              :msg,
              :time,
              :level,
              :file,
              :line,
              :mfa,
              :pid,
              :request_id,
              :trace_id,
              :span_id
            ]
          }}
     }}
  ]
end

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :hackney, mod_metrics: :hackney_telemetry

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
