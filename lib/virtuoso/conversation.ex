defmodule Virtuoso.Conversation do
  @moduledoc """
  GenServer to maintain conversation state
  """

  use GenServer
  require Logger

  alias Virtuoso.Conversation.Supervisor
  alias Virtuoso.Executive

  defmodule State do
    @moduledoc """
    Struct for Conversation state
    """
    @environment Application.get_env(:virtuoso, :environment)

    @doc """
    Conversation state

    - `:sender_id` - the facebook sender id
    - `:last_recieved_at` - when the last message was received for this conversation
    - `:messages` - a list of sent and received responses
    - `:pid` - the conversation process identification tuple
    - `:environment` - config enviroment var, used for ignoring Ecto-related code in process tests
    """
    defstruct [
      :sender_id,
      :last_recieved_at,
      :messages,
      :pid,
      environment: @environment
    ]
  end

  @typedoc """
  Conversation state
  """
  @type state :: %State{}

  @typedoc """
  Sender id for facebook messages
  """
  @type sender_id :: String.t()

  @timeout_period 60 * 1000 # one minute

  @doc false
  def start_link(sender_id) do
    GenServer.start_link(__MODULE__, sender_id, name: pid(sender_id))
  end

  @doc """
  Helper for determining a conversation registered process name
  """
  @spec pid(sender_id()) :: tuple()
  def pid(sender_id) do
    {:via, Registry, {Virtuoso.Conversation.Registry, sender_id}}
  end

  @doc """
  A message is received. Ensure the process is alive and forward it
  """
  @spec received_message(map()) :: :ok
  def received_message(%{sender_id: sender_id} = entry) do
    ensure_process(sender_id)
    GenServer.cast(pid(sender_id), {:received, entry})
    conversation_pid = pid(sender_id)
    {entry, conversation_pid}
  end

  @doc """
  A message is sent. Ensure the process is alive and forward it
  """
  @spec sent_message(sender_id(), map()) :: :ok
  def sent_message(sender_id, response) do
    ensure_process(sender_id)
    GenServer.cast(pid(sender_id), {:sent, response})
  end

  @doc """
  Ensure a process is alive before sending data to it
  """
  @spec ensure_process(sender_id()) :: :ok
  def ensure_process(sender_id) do
    case Registry.whereis_name({Virtuoso.Conversation.Registry, sender_id}) do
      :undefined -> Supervisor.start_child(sender_id)
      _ -> :ok
    end
  end

  @doc """
  Terminate a conversation process
  """
  @spec terminate(sender_id()) :: :ok
  def terminate(sender_id) do
    GenServer.call(pid(sender_id), :terminate)
  end

  #
  # Server
  #

  def init(sender_id) do
    Logger.info("Starting conversation for #{sender_id}")

    self() |> schedule_timeout()

    state = %State{
      last_recieved_at: Timex.now(),
      messages: [],
      pid: pid(sender_id),
      sender_id: sender_id,
    }

    {:ok, state}
  end

  def handle_call(:terminate, _from, state) do
    Logger.info("Terminating process: #{inspect(state)}")

    {:stop, :normal, :ok, state}
  end

  def handle_cast({:received, entry}, state) do
    Logger.info("Received a message for #{state.sender_id}")

    Executive.handles_message({entry, state})

    new_state =
      state
      |> Map.put(:last_recieved_at, Timex.now())
      |> Map.put(:messages, [entry | state.messages])

    {:noreply, new_state}
  end
  def handle_cast({:sent, response}, state) do
    Logger.info("Sent a message to #{state.sender_id}")

    new_state =
      state
      |> Map.put(:messages, [response | state.messages])

    {:noreply, new_state}
  end

  defp schedule_timeout(pid) do
    Logger.debug(fn () -> "Scheduling timeout for #{inspect(pid)}" end)
    :erlang.send_after(@timeout_period, pid, :timeout)
  end
end
