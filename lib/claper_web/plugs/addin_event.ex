defmodule ClaperWeb.Plugs.AddinEvent do
  @moduledoc """
  Assigns the event a sidebar request is about as `:addin_event`.

  An event key has already set it in `ClaperWeb.Plugs.AddinToken`. With a
  personal key the request names the event, and the user has to lead it.
  """

  import Plug.Conn

  @event_preload [presentation_file: [:presentation_state]]

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{addin_event: _}} = conn, _opts), do: conn

  def call(%Plug.Conn{assigns: %{addin_user: user}} = conn, _opts) do
    case named_event(conn) do
      nil ->
        error(conn, 400, "name the event with an x-claper-event header")

      code ->
        assign_led_event(conn, user, code)
    end
  end

  def call(conn, _opts), do: error(conn, 401, "unauthorized")

  # An event someone else leads gets the same answer as a missing one, so a key
  # cannot probe which codes exist.
  defp assign_led_event(conn, user, code) do
    with %Claper.Events.Event{} = event <-
           Claper.Events.get_event_with_code(code, @event_preload),
         true <- Claper.Events.leads_event?(event, user) do
      assign(conn, :addin_event, event)
    else
      _ -> error(conn, 404, "no such event")
    end
  end

  # A header works the same for GET and POST and cannot collide with a body field.
  defp named_event(conn) do
    case get_req_header(conn, "x-claper-event") do
      [code | _] when is_binary(code) -> String.trim(code) |> presence()
      _ -> conn.params["event"] |> presence()
    end
  end

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_), do: nil

  defp error(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: message}))
    |> halt()
  end
end
