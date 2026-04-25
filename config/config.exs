import Config

config :soot_core,
  ash_domains: [SootCore.Domain]

config :ash_pki,
  ash_domains: [AshPki.Domain]

if File.exists?(Path.join([__DIR__, "#{config_env()}.exs"])) do
  import_config "#{config_env()}.exs"
end
