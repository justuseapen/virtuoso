defmodule Mix.Tasks.Virtuoso.Gen.Platform do
  @moduledoc """
  Generates configuration for a new platform and client configuration.
  """
  use Mix.Task
  alias Mix.Generator

  def run(args) do
    [medium_client|_] = args
    # validate_medium_client

    # md `lib/platform/$PLATFORM/` directory
    Generator.create_directory("lib/#{medium_client}")

    # md `lib/platform/$PLATFORM/config/`
    Generator.create_directory("lib/#{medium_client}/config")
    Generator.create_file("lib/#{medium_client}/config/dev.secret.exs", platform_config_template)
    Generator.create_file("lib/#{medium_client}/config/prod.secret.exs", platform_config_template)
    Generator.create_file("lib/#{medium_client}/config/test.exs", platform_config_template)
  end

  def platform_config_template() do
    """
    use Mix.Config

    #{platform_client_configuration_partial}
    """
  end

  def platform_client_config() do
    """
    config :fb_page_name,
      page_access_token: "",
      recipient_id: ""
    """
  end
end
