defmodule VirtuosoDashboardWeb.ChatLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint VirtuosoDashboardWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Virtuoso.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Virtuoso.Repo, {:shared, self()})
    {:ok, conn: build_conn()}
  end

  # PubSub → LiveView delivery is async; poll briefly instead of sleeping.
  defp eventually(fun, tries \\ 50) do
    if fun.() do
      :ok
    else
      if tries == 0, do: flunk("condition never became true")
      Process.sleep(20)
      eventually(fun, tries - 1)
    end
  end

  test "chat: send a message, get the stubbed reply, see the run card", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    assert html =~ "Virtuoso Chat"

    view
    |> form("#chat-form", chat: %{text: "hello world"})
    |> render_submit()

    # The user's message renders immediately.
    assert render(view) =~ "hello world"

    # The async deliver completes with the stub reply.
    assert render_async(view, 5_000) =~ "stub reply: hello world"

    # The engine panel shows this conversation's run (decision + votes).
    eventually(fn -> render(view) =~ "answer" and render(view) =~ "3/3" end)
  end

  test "greeting renders a fast-path card, not an ensemble run", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> form("#chat-form", chat: %{text: "hi"}) |> render_submit()

    assert render_async(view, 5_000) =~ "fast path"
  end

  test "transcript survives a reload via the event log", %{conn: conn} do
    # Prime the session cookie first: live/2 doesn't return the conn, so both
    # live mounts below recycle THIS response's cookie = same conversation_id.
    conn = get(conn, "/")

    {:ok, view, _html} = live(conn, "/")
    view |> form("#chat-form", chat: %{text: "remember me"}) |> render_submit()
    assert render_async(view, 5_000) =~ "stub reply: remember me"

    # Same conn = same session cookie = same conversation_id.
    {:ok, _view2, html2} = live(conn, "/")
    assert html2 =~ "remember me"
    assert html2 =~ "stub reply: remember me"
  end

  test "dashboard still renders at /dashboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/dashboard")
    assert html =~ "live ensemble dashboard"
  end

  # Regression: fast-path detection must survive the runs panel filling up
  # (@keep_runs caps the list at 8; the check uses a monotonic counter).
  test "no spurious fast-path cards after more runs than the panel keeps", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    for i <- 1..10 do
      view |> form("#chat-form", chat: %{text: "question number #{i}"}) |> render_submit()
      assert render_async(view, 5_000) =~ "stub reply: question number #{i}"
      # Wait for this turn's run card so the counter is settled before the next send.
      eventually(fn -> length(:sys.get_state(view.pid).socket.assigns.runs) == min(i, 8) end)
    end

    refute render(view) =~ "fast path"
  end

  # Regression: a budget-refused turn ran no ensemble, but it is NOT the fast
  # path — the panel must not claim "0 tokens, no LLM" for a refusal.
  test "budget refusal is not labeled as the fast path", %{conn: conn} do
    :ok = Virtuoso.Budget.kill_switch(true)
    on_exit(fn -> Virtuoso.Budget.kill_switch(false) end)

    {:ok, view, _html} = live(conn, "/")
    view |> form("#chat-form", chat: %{text: "anything at all"}) |> render_submit()

    # Match a fragment without the apostrophe — HEEx escapes ' to &#39;.
    assert render_async(view, 5_000) =~ "reached my usage limit"
    refute render(view) =~ "fast path"
  end
end
