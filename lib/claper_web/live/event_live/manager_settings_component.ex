defmodule ClaperWeb.EventLive.ManagerSettingsComponent do
  use ClaperWeb, :live_component

  def render(assigns) do
    assigns = assigns |> assign_new(:show_shortcut, fn -> true end)

    ~H"""
    <div class="flex flex-col gap-4 p-4">
      <ClaperWeb.EventLive.ManageInteractionOptionsComponent.render
        current_interaction={@current_interaction}
        state={@state}
        create={@create}
        show_shortcut={@show_shortcut}
      />
      <ClaperWeb.EventLive.ManagePresentationOptionsComponent.render
        state={@state}
        create={@create}
        show_shortcut={@show_shortcut}
      />
      <ClaperWeb.EventLive.ManageAttendeesOptionsComponent.render
        state={@state}
        create={@create}
        show_shortcut={@show_shortcut}
      />
      <ClaperWeb.EventLive.ManagePresenterEmbedComponent.render
        embed_exists={@presenter_embed_exists}
        embed_url={@presenter_embed_url}
      />
    </div>
    """
  end
end
