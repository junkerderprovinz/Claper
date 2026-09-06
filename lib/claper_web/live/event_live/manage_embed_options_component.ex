defmodule ClaperWeb.EventLive.ManageEmbedOptionsComponent do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  attr :embed_exists, :boolean, required: true
  attr :embed_url, :string, default: nil

  def render(assigns) do
    # Without an allow list the browser refuses to display the link anywhere,
    # so the card says whether this server has one rather than letting someone
    # create a link and wonder why the frame stays empty.
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

        <div class="flex flex-wrap gap-2">
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
            "The link shows the same slides and interactions as the projected view, in a compact layout and without the joining instructions. Use the presentation settings above to hide the messages before you embed it."
          )}
        </p>

        <p :if={!@frame_ancestors_configured} class="text-xs text-orange-700">
          {gettext(
            "This server does not allow any site to embed it yet. Set EMBED_FRAME_ANCESTORS to the origins that may frame the link, otherwise the browser refuses to display it."
          )}
        </p>

        <p class="text-xs text-gray-500">
          {gettext(
            "Revoking or replacing the link disconnects embeds that are already open, and so does ending the event. Letting the event expire or deleting it only stops new visitors. Slide images stay reachable either way, because this server publishes them at a fixed address whether or not a link exists."
          )}
        </p>
      </div>
    </div>
    """
  end

  # Asks the plug that writes the header, not a second check of its own. A value
  # the plug rejects as a whole, a bare wildcard or a quoted string all end up
  # as 'none', and the card has to say so instead of reporting the variable as
  # set.
  defp frame_ancestors_configured?, do: ClaperWeb.Plugs.EmbedFrame.framing_allowed?()
end
