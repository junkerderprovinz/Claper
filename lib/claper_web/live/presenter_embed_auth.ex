defmodule ClaperWeb.PresenterEmbedAuth do
  @moduledoc """
  Authorizes the embeddable presenter view from the token in its URL.

  The WebSocket mount skips the router pipeline, and a link can be revoked
  before it connects, so the token is checked again here. No user is taken from
  the session: the view is read-only whoever opens it.
  """

  use ClaperWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  @event_preload [:user, presentation_file: [:polls, :presentation_state]]

  def on_mount(:default, %{"token" => token}, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    event =
      if ClaperWeb.Plugs.PresenterEmbedFrame.framing_allowed?() do
        Claper.Events.get_event_by_presenter_embed_token(token, @event_preload)
      end

    case event do
      nil ->
        # A path the token plug rejects with its 404. "/" is framable and would put
        # an unrelated Claper page on the host document, and repeating the token
        # would write it into any log that records the redirect.
        {:halt, redirect(socket, to: "/embed/presenter/ended")}

      event ->
        {:cont,
         socket
         # The raw token stays out of the assigns, which a crash report writes to the log.
         |> assign(:current_user, nil)
         |> assign(:presenter_embed, true)
         |> assign(:embed_event, event)}
    end
  end

  def on_mount(:default, _params, _session, socket),
    do: {:halt, redirect(socket, to: "/embed/presenter/ended")}
end
