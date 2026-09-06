defmodule ClaperWeb.Plugs.AddinEvent do
  @moduledoc """
  Settles which event a sidebar request is about.

  An event key already answers that by itself, and `ClaperWeb.Plugs.AddinToken`
  has assigned it. A personal key does not: it belongs to a person who may lead
  many events, so the request names one and this checks that they lead it.

  Either way the actions behind this see the same `:addin_event`, which is why
  none of them has to know which key was used.
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
        case Claper.Events.get_event_with_code(code, @event_preload) do
          # The same answer for an event that does not exist and one this person
          # does not lead, so the key cannot be used to find out which codes are
          # taken.
          %Claper.Events.Event{} = event ->
            if Claper.Events.leads_event?(event, user),
              do: assign(conn, :addin_event, event),
              else: error(conn, 404, "no such event")

          nil ->
            error(conn, 404, "no such event")
        end
    end
  end

  def call(conn, _opts), do: error(conn, 401, "unauthorized")

  # A header rather than a parameter, so the same shape works for a GET and for
  # a body-carrying POST without ever colliding with a field of the body.
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
