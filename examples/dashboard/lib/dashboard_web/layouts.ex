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
        <title>Virtuoso Dashboard</title>
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
