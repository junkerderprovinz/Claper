defmodule ClaperWeb.Plugs.EmbedCatalogToken do
  @moduledoc """
  Authenticates the interaction catalogue by the read-only embed token in the
  path. A block on a slide only reads, so it never needs the sidebar's key.
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
