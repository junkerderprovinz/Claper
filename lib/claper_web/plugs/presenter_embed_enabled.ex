defmodule ClaperWeb.Plugs.PresenterEmbedEnabled do
  @moduledoc """
  Answers 404 while presenter embedding is off.

  It asks `ClaperWeb.Plugs.PresenterEmbedFrame` so that a value that plug rejects
  counts as off here too. The add-in's static pages are served by `Plug.Static`
  in the endpoint and are not covered.
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
