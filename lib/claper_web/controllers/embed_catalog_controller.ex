defmodule ClaperWeb.EmbedCatalogController do
  @moduledoc """
  Lists the polls, quizzes and forms of an embedded event, so a slide block can
  offer them for selection.

  It is reached with the read-only embed token and returns titles and ids only.
  Options and results stay behind the presenter view's own rules.
  """

  use ClaperWeb, :controller

  def index(%{assigns: %{embed_event: event}} = conn, _params) do
    {polls, quizzes, forms} =
      case event.presentation_file do
        nil ->
          {[], [], []}

        file ->
          {Claper.Polls.list_polls(file.id), Claper.Quizzes.list_quizzes(file.id),
           Claper.Forms.list_forms(file.id)}
      end

    json(conn, %{
      event: %{name: event.name},
      polls: Enum.map(polls, &%{id: &1.id, title: &1.title}),
      quizzes: Enum.map(quizzes, &%{id: &1.id, title: &1.title}),
      forms: Enum.map(forms, &%{id: &1.id, title: &1.title})
    })
  end
end
