defmodule ClaperWeb.EventLive.ManagePresenterEmbedComponent do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  attr :embed_exists, :boolean, required: true
  attr :embed_url, :string, default: nil
  attr :addin_token_exists, :boolean, default: false
  attr :addin_token, :string, default: nil

  def render(assigns) do
    # Without an allow list the feature is off: the route answers 404 and the
    # browser would refuse to frame the page anyway. The card says so and hides
    # the buttons rather than handing out a link that cannot be opened.
    assigns = assign_new(assigns, :frame_ancestors_configured, &frame_ancestors_configured?/0)

    ~H"""
    <div
      class="flex flex-col gap-2 border border-gray-200 rounded-2xl p-2 bg-white shadow-lg"
      x-data="{ copied: false }"
    >
      <div class="flex items-center gap-2">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="icon icon-tabler icons-tabler-outline icon-tabler-code shrink-0 text-[#140553]"
        >
          <path stroke="none" d="M0 0h24v24H0z" fill="none" />
          <path d="M7 8l-4 4l4 4" />
          <path d="M17 8l4 4l-4 4" />
          <path d="M14 4l-4 16" />
        </svg>
        <span class="font-bold text-sm text-[#140553]">{gettext("Embed link")}</span>
      </div>

      <div class="space-y-2 px-1">
        <p class="text-xs text-gray-700">
          {gettext(
            "Show this event's presenter view as a live web page inside another document, for example a slide deck. The link is read-only: it cannot change the presentation and it grants no account access."
          )}
        </p>

        <div :if={@embed_url} class="space-y-2">
          <p class="text-xs font-semibold text-gray-900">
            {gettext("Copy the link now. It is stored hashed and cannot be shown again.")}
          </p>
          <input
            type="text"
            readonly
            value={@embed_url}
            x-ref="embedUrl"
            onclick="this.select()"
            class="w-full text-xs rounded-full border border-gray-200 px-3 py-2 bg-gray-50 text-gray-700"
          />
          <button
            type="button"
            class="btn btn-secondary btn-sm w-full"
            x-on:click="navigator.clipboard.writeText($refs.embedUrl.value); copied = true; setTimeout(() => copied = false, 2000)"
          >
            <span x-show="!copied">{gettext("Copy link")}</span>
            <span x-show="copied" x-cloak>{gettext("Copied")}</span>
          </button>
        </div>

        <p :if={@embed_exists && is_nil(@embed_url)} class="text-xs text-gray-700">
          {gettext(
            "An embed link is active. Anyone holding it can watch this event. Create a new one to replace it, or revoke it to switch it off."
          )}
        </p>

        <%!-- Without an allow list the route answers 404 for every token, so a link
        created here could not be opened at all. The buttons go with it rather
        than handing out something that cannot work. --%>
        <div :if={@frame_ancestors_configured} class="flex flex-wrap gap-2">
          <button
            type="button"
            phx-click="create-presenter-embed-token"
            data-confirm={
              if @embed_exists,
                do:
                  gettext(
                    "Replace the embed link? The current one stops working and open embeds are disconnected."
                  )
            }
            class="btn btn-gradient btn-sm"
          >
            {if @embed_exists, do: gettext("Create a new link"), else: gettext("Create embed link")}
          </button>
          <button
            :if={@embed_exists}
            type="button"
            phx-click="revoke-presenter-embed-token"
            data-confirm={gettext("Revoke the embed link? Open embeds stop working immediately.")}
            class="btn btn-secondary btn-sm"
          >
            {gettext("Revoke")}
          </button>
        </div>

        <p class="text-xs text-gray-500">
          {gettext(
            "The link shows the page you are projecting and the interactions you have released, in a compact layout and without the joining instructions. Pages you have not reached are not sent. Use the presentation settings above to hide the messages before you embed it."
          )}
        </p>

        <p :if={!@frame_ancestors_configured} class="text-xs text-orange-700">
          {gettext(
            "This server does not allow any site to embed it yet. Set PRESENTER_EMBED_FRAME_ANCESTORS to the origins that may frame the link, otherwise the browser refuses to display it."
          )}
        </p>

        <p class="text-xs text-gray-500">
          {gettext(
            "Revoking or replacing the link disconnects embeds that are already open, and so does ending the event. Letting the event expire or deleting it only stops new visitors. Slide images stay reachable either way, because this server publishes them at a fixed address whether or not a link exists."
          )}
        </p>

        <%!-- The sidebar token is the writing one. It is shown separately and
        described separately, because the difference between the two decides
        whether a token may travel inside a shared file. --%>
        <div :if={@frame_ancestors_configured} class="border-t border-gray-200 pt-2 mt-1">
          <p class="text-xs font-semibold text-gray-900">
            {gettext("PowerPoint sidebar")}
          </p>
          <p class="text-xs text-gray-500 mt-1">
            {gettext(
              "The sidebar creates polls from inside PowerPoint. Its token can write, so keep it on your own computer and never inside a presentation you share."
            )}
          </p>

          <%!-- The token is useless without the add-in, and the add-in is not in
          any store: a self-hosted server has to hand out its own manifests. So
          the way to get it sits next to the key it needs. --%>
          <.link
            href="/addin"
            target="_blank"
            class="text-xs text-primary-600 underline mt-1 inline-block"
          >
            {gettext("How to add Claper to PowerPoint")}
          </.link>

          <div :if={@addin_token} class="space-y-2 mt-2">
            <input
              type="text"
              readonly
              value={@addin_token}
              onclick="this.select()"
              class="w-full text-xs rounded-full border border-gray-200 px-3 py-2 bg-gray-50 text-gray-700"
            />
            <p class="text-xs font-semibold text-gray-900">
              {gettext("Copy it now. It is stored hashed and cannot be shown again.")}
            </p>
          </div>

          <div class="flex flex-wrap gap-2 mt-2">
            <button
              type="button"
              phx-click="create-addin-token"
              data-confirm={
                if @addin_token_exists,
                  do: gettext("Replace the sidebar token? The current one stops working.")
              }
              class="btn btn-secondary btn-sm"
            >
              {if @addin_token_exists,
                do: gettext("New sidebar token"),
                else: gettext("Create sidebar token")}
            </button>
            <button
              :if={@addin_token_exists}
              type="button"
              phx-click="revoke-addin-token"
              data-confirm={gettext("Revoke the sidebar token?")}
              class="btn btn-secondary btn-sm"
            >
              {gettext("Revoke")}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Asks the plug that writes the header, not a second check of its own. A value
  # the plug rejects as a whole, a bare wildcard or a quoted string all end up
  # as 'none', and the card has to say so instead of reporting the variable as
  # set.
  defp frame_ancestors_configured?, do: ClaperWeb.Plugs.PresenterEmbedFrame.framing_allowed?()
end
