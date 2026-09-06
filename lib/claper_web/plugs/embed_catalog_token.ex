defmodule ClaperWeb.Plugs.EmbedCatalogToken do
  @moduledoc """
  Authenticates the read-only catalogue by the embed token in the path.

  Same token as `/embed/interaction/:token`, and deliberately not the sidebar's
  writing one: a block sitting on a slide needs to know which interactions it
  could show, and nothing more.

  Answers JSON rather than the HTML 404 `ClaperWeb.Plugs.PresenterEmbedToken`
  renders, because the caller here is a fetch from a slide, not a browser
  following a link.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"token" => token}} = conn, _opts) do
    with true <- ClaperWeb.Plugs.PresenterEmbedFrame.framing_allowed?(),
         event when not is_nil(event) <-
           Claper.Events.get_event_by_presenter_embed_token(token,
             presentation_file: [:presentation_state]
           ) do
      assign(conn, :embed_event, event)
    else
      _ -> not_found(conn)
    end
  end

  def call(conn, _opts), do: not_found(conn)

  defp not_found(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, ~s({"error":"no such link"}))
    |> halt()
  end
end
