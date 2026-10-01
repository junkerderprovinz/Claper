defmodule ClaperWeb.Plugs.AddinToken do
  @moduledoc """
  Authenticates the PowerPoint sidebar by its bearer token.

  An event key is assigned as `:addin_event` and reaches that event only. A
  personal key is assigned as `:addin_user` and lets the sidebar create events;
  requests made with it name the event they act on. Neither is accepted in place
  of the read-only embed token, or the other way round.
  """

  import Plug.Conn

  @event_preload [presentation_file: [:presentation_state]]

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, conn} <- resolve(conn, token) do
      conn
    else
      _ -> unauthorized(conn)
    end
  end

  # The narrower event key wins if a token ever matched both.
  defp resolve(conn, token) do
    cond do
      event = Claper.Events.get_event_by_addin_token(token, @event_preload) ->
        {:ok, assign(conn, :addin_event, event)}

      user = Claper.Accounts.get_user_by_addin_account_token(token) ->
        {:ok, assign(conn, :addin_user, user)}

      true ->
        :error
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"unauthorized"}))
    |> halt()
  end
end
