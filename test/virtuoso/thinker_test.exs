defmodule Virtuoso.ThinkerTest do
  use ExUnit.Case

  alias Virtuoso.Thinker

  test "module_thinker_client" do
    assert Virtuoso.Thinker.Watson.Client == Thinker.module_thinker_client(:watson)
    assert Virtuoso.Thinker.Wit.Client == Thinker.module_thinker_client(:wit)
  end

  test "module_thinker_slow_thinking" do
    assert Virtuoso.Thinker.Watson.SlowThinking == Thinker.module_thinker_slow_thinking(:watson)
    assert Virtuoso.Thinker.Wit.SlowThinking == Thinker.module_thinker_slow_thinking(:wit)
  end

end
