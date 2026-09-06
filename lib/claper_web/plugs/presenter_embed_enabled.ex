defmodule ClaperWeb.Plugs.PresenterEmbedEnabled do
  @moduledoc """
  Refuses everything when the presenter embed feature is switched off.

  The switch is the same one the embed routes use, so a server that never opted
  in serves neither the embeddable views nor the API behind them. It asks
  `ClaperWeb.Plugs.PresenterEmbedFrame` rather than reading the setting again,
  because a value that plug rejects as a whole must count as off here too.

  It does not reach the add-in's own two pages. `/addin/sidebar.html` and
  `/addin/slide.html` are static files under `ClaperWeb.static_paths/0`, so
  `Plug.Static` answers them in the endpoint, before any router pipeline runs.
  They stay reachable with the feature off and simply have nothing to talk to.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      ClaperWeb.Plugs.PresenterEmbedFrame.framing_allowed?() -> conn
      html?(conn) -> not_found_page(conn)
      true -> not_found_json(conn)
    end
  end

  # The switch also guards a page people open in a browser, and a JSON body is
  # the wrong thing to show them. The API routes keep the JSON they can parse.
  defp html?(conn), do: conn.private[:phoenix_format] == "html"

  defp not_found_page(conn) do
    conn
    |> put_status(:not_found)
    |> Phoenix.Controller.put_root_layout(html: false)
    |> Phoenix.Controller.put_view(ClaperWeb.ErrorView)
    |> Phoenix.Controller.render("404.html")
    |> halt()
  end

  defp not_found_json(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, ~s({"error":"not found"}))
    |> halt()
  end
end
