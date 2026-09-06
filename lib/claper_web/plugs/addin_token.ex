defmodule ClaperWeb.Plugs.AddinToken do
  @moduledoc """
  Authenticates the PowerPoint sidebar by its event scoped token.

  The token arrives as `Authorization: Bearer <token>` and resolves to exactly
  one event, which is assigned as `:addin_event`. Everything the API does is
  scoped to that event, so a token can only ever reach what it was issued for.

  This is deliberately not the read-only embed token: the sidebar writes, the
  embed does not, and the two must not be interchangeable.
  """

  import Plug.Conn

  @event_preload [presentation_file: [:presentation_state]]

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         event when not is_nil(event) <-
           Claper.Events.get_event_by_addin_token(token, @event_preload) do
      assign(conn, :addin_event, event)
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"unauthorized"}))
    |> halt()
  end
end
