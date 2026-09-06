defmodule ClaperWeb.Plugs.PresenterEmbedToken do
  @moduledoc """
  Verifies the embeddable presenter token carried in the request path.

  Renders a 404 page when the token is unknown, revoked or its event expired.
  A redirect is deliberately avoided: this route is meant to be framed by a
  third party, and redirecting would render an unrelated Claper page, including
  the join screen, inside that frame.

  This plug guards the initial HTML response only. The LiveView WebSocket mount
  does not go through the router pipeline, so `ClaperWeb.PresenterEmbedAuth`
  checks the same token again there.

  A server without an allow list answers 404 for every token. `frame-ancestors
  'none'` already stops a browser from framing the page, but the link stays
  openable in a tab of its own, so the header alone is not an off switch.
  `EMBED_FRAME_ANCESTORS` is therefore what turns the whole feature on, and it
  is unset by default.
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"token" => token}} = conn, _opts) do
    if ClaperWeb.Plugs.EmbedFrame.framing_allowed?() and
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
