defmodule ClaperWeb.Plugs.AddinToken do
  @moduledoc """
  Authenticates the PowerPoint sidebar, by either of the two keys it can hold.

  The token arrives as `Authorization: Bearer <token>`.

  An **event key** resolves to exactly one event, assigned as `:addin_event`.
  Everything done with it is scoped to that event, so it can only ever reach
  what it was issued for.

  A **personal key** resolves to a person, assigned as `:addin_user`. It exists
  because an event key cannot create an event, so a new presentation could never
  get an event of its own without leaving PowerPoint. Requests made with it name
  the event they mean, and the controller checks that this person leads it.

  Neither is the read-only embed token: the sidebar writes, the embed does not,
  and the three must not be interchangeable.
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

  # An event key is tried first because it is the narrower one: a value that
  # somehow satisfied both should get the smaller of the two.
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
