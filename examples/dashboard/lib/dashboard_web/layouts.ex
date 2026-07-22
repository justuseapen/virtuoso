defmodule VirtuosoDashboardWeb.Layouts do
  @moduledoc false
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Virtuoso — chat showcase</title>
        <style>
          :root { color-scheme: light dark; }
          body {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            margin: 0; padding: 1.5rem; background: #11151c; color: #d8dee9;
          }
          h1 { font-size: 1.2rem; margin: 0 0 0.25rem; color: #88c0d0; }
          h2 { font-size: 0.95rem; margin: 1.5rem 0 0.5rem; color: #81a1c1; }
          .sub { color: #616e88; font-size: 0.8rem; margin-bottom: 1rem; }
          table { border-collapse: collapse; width: 100%; font-size: 0.8rem; }
          th, td { text-align: left; padding: 0.3rem 0.75rem 0.3rem 0; }
          th { color: #616e88; font-weight: normal; border-bottom: 1px solid #2e3440; }
          tr + tr td { border-top: 1px solid #1c2230; }
          .ok { color: #a3be8c; } .warn { color: #ebcb8b; } .err { color: #bf616a; }
          button {
            background: #5e81ac; color: #eceff4; border: 0; border-radius: 4px;
            padding: 0.45rem 0.9rem; font: inherit; cursor: pointer;
          }
          button:hover { background: #81a1c1; }
          .stat { display: inline-block; margin-right: 1.5rem; }
          .stat b { color: #88c0d0; }
          .empty { color: #4c566a; font-style: italic; padding: 0.5rem 0; }
          .chat-page { display: grid; grid-template-columns: minmax(0, 2fr) minmax(260px, 1fr);
                       gap: 2rem; max-width: 1100px; }
          @media (max-width: 800px) { .chat-page { grid-template-columns: 1fr; } }
          .messages { display: flex; flex-direction: column; gap: 0.5rem; margin: 1rem 0;
                      min-height: 300px; }
          .msg { max-width: 85%; padding: 0.5rem 0.75rem; border-radius: 8px; }
          .msg p { margin: 0.15rem 0 0; white-space: pre-wrap; }
          .msg .who { font-size: 0.7rem; color: #616e88; }
          .msg.user { align-self: flex-end; background: #2e3440; }
          .msg.assistant { align-self: flex-start; background: #1c2230; }
          .msg.thinking p { color: #616e88; font-style: italic; }
          #chat-form { display: flex; gap: 0.5rem; }
          #chat-form input { flex: 1; background: #1c2230; color: #d8dee9; border: 1px solid #2e3440;
                             border-radius: 4px; padding: 0.5rem 0.75rem; font: inherit; }
          .run-card { display: flex; flex-direction: column; gap: 0.15rem; font-size: 0.78rem;
                      border: 1px solid #2e3440; border-radius: 6px; padding: 0.5rem 0.7rem;
                      margin-bottom: 0.5rem; }
          .budget-row { font-size: 0.8rem; margin-bottom: 0.25rem; }
          .budget-row b { color: #88c0d0; }
          a { color: #81a1c1; }
        </style>
      </head>
      <body>
        {@inner_content}
        <script src="/assets/phoenix/phoenix.min.js">
        </script>
        <script src="/assets/phoenix_live_view/phoenix_live_view.min.js">
        </script>
        <script>
          const csrf = document.querySelector("meta[name='csrf-token']").content;
          const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
            params: { _csrf_token: csrf }
          });
          liveSocket.connect();
        </script>
      </body>
    </html>
    """
  end
end
