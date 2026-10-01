defmodule ClaperWeb.Plugs.PresenterEmbedToken do
  @moduledoc """
  Verifies the presenter embed token in the request path.

  An unknown, revoked or expired token gets a 404 page rather than a redirect,
  which would put an unrelated Claper page inside a third party's frame. Without
  a frame-ancestors allow list every token gets the 404, since `'none'` stops
  framing but not opening the link in a tab. The LiveView mount checks the token
  again in `ClaperWeb.PresenterEmbedAuth`.
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"token" => token}} = conn, _opts) do
    if ClaperWeb.Plugs.PresenterEmbedFrame.framing_allowed?() and
         Claper.Events.get_event_by_presenter_embed_token(token) do
      conn
    else
      halt_not_found(conn)
    end
  end

  def call(conn, _opts), do: halt_not_found(conn)

  defp halt_not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_root_layout(html: false)
    |> put_view(ClaperWeb.ErrorView)
    |> render("404.html")
    |> halt()
  end
end
