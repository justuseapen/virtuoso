defmodule MementoMori.Routine.TimeLeftTest do
  use  ExUnit.Case

  alias MementoMori.Routine.TimeLeft
  alias Virtuoso.Impression

  test "run/1" do
    impression = %Impression{
      message: "How much time do I have left?",
      sender_id: "TEST_SENDER",
      recipient_id: "RECIPIENT_ID",
      intent: MementoMori.Routine.TimeLeft
    }

    assert TimeLeft.run(impression) == "That depends. How old are you?"
  end
end

