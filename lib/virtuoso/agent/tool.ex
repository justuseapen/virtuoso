defmodule Virtuoso.Agent.Tool do
  @moduledoc """
  Behaviour for tools that agents can invoke during conversations.

  Tools let agents take actions — look up data, call APIs, perform calculations,
  etc. Each tool declares its name, description, and parameter schema so the LLM
  knows when and how to use it.

  ## Example

      defmodule MyApp.Tools.Weather do
        use Virtuoso.Agent.Tool

        @impl true
        def name, do: "get_weather"

        @impl true
        def description, do: "Get the current weather for a location."

        @impl true
        def parameters do
          %{
            type: "object",
            properties: %{
              location: %{type: "string", description: "City name or zip code"}
            },
            required: ["location"]
          }
        end

        @impl true
        def execute(%{"location" => location}, _context) do
          # Call weather API...
          {:ok, "72°F and sunny in \#{location}"}
        end
      end
  """

  @doc "Unique name for this tool (used in LLM function calling)."
  @callback name() :: String.t()

  @doc "Human-readable description of what this tool does."
  @callback description() :: String.t()

  @doc "JSON Schema describing the tool's input parameters."
  @callback parameters() :: map()

  @doc """
  Execute the tool with the given parameters.

  `params` is a map of parameter values decoded from the LLM's tool call.
  `context` contains `%{impression: impression}` for access to the current message.
  """
  @callback execute(params :: map(), context :: map()) ::
              {:ok, String.t()} | {:error, String.t()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Virtuoso.Agent.Tool

      @doc """
      Returns the tool definition map used by LLM providers.
      """
      def definition do
        %{
          name: name(),
          description: description(),
          input_schema: parameters()
        }
      end

      defoverridable []
    end
  end
end
