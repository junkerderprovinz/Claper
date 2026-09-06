defmodule ClaperWeb.PresenterEmbedAuth do
  @moduledoc """
  Authorizes the embeddable presenter view from the token in its URL.

  The check is repeated here rather than left to
  `ClaperWeb.Plugs.PresenterEmbedToken` because the LiveView WebSocket mount
  never goes through the router pipeline, and because a link can be revoked
  between the initial HTML response and the connected mount.

  No identity is taken from the session. The route is framed cross-origin and
  has to work without a cookie, and a cookie that does happen to be sent must
  not turn into one, so `:current_user` is pinned to `nil` instead of being
  carried over. The locale is the one thing still read from the session, and in
  a cross-origin frame under `SameSite=Lax` no cookie arrives at all, so an
  embedded view renders in the default language.
  """

  use ClaperWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  @event_preload [:user, presentation_file: [:polls, :presentation_state]]

  def on_mount(:default, %{"token" => token}, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    case Claper.Events.get_event_by_presenter_embed_token(token, @event_preload) do
      nil ->
        # A path the token check cannot accept, so the plug answers with its
        # 404. Sending the frame to "/" would put an unrelated Claper page on
        # someone else's document, and "/" is served with
        # `x-frame-options: ALLOWALL`, so the browser would happily show it. The
        # rejected token is not put back into the URL either, so it stays out of
        # the redirect and out of any log that records one.
        {:halt, redirect(socket, to: "/embed/presenter/ended")}

      event ->
        {:cont,
         socket
         # The raw token is deliberately NOT kept. Anyone holding the link can
         # reach this view, and a crash report writes the whole socket to the
         # log, so a secret in the assigns is a secret on disk.
         |> assign(:current_user, nil)
         |> assign(:presenter_embed, true)
         |> assign(:embed_event, event)}
    end
  end

  # Same destination as a rejected token, for the same reason: "/" is an
  # unrelated Claper page and it is served with `x-frame-options: ALLOWALL`, so
  # it would appear on the third party document this route is embedded in.
  def on_mount(:default, _params, _session, socket),
    do: {:halt, redirect(socket, to: "/embed/presenter/ended")}
end
