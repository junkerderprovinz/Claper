defmodule ClaperWeb.EmbedCatalogController do
  @moduledoc """
  What a block on a slide may offer to show.

  A block is placed once and then has to be told what it displays. Without this
  the only way to say so is a hand-built URL carrying `?poll=16`, which means
  reading ids out of another screen and editing query strings on a slide. This
  returns the names and ids of what exists, so the block can offer a list.

  Read-only by construction: it is reached with the embed token, and it returns
  titles and ids only. No options, no counts, no correct answers. Those stay
  behind the presenter view's own release rules, which decide per interaction
  whether results may leave the presenter's screen at all.
  """

  use ClaperWeb, :controller

  def index(%{assigns: %{embed_event: event}} = conn, _params) do
    {polls, quizzes} =
      case event.presentation_file do
        nil ->
          {[], []}

        file ->
          {Claper.Polls.list_polls(file.id), Claper.Quizzes.list_quizzes(file.id)}
      end

    json(conn, %{
      event: %{name: event.name},
      polls: Enum.map(polls, &%{id: &1.id, title: &1.title}),
      quizzes: Enum.map(quizzes, &%{id: &1.id, title: &1.title})
    })
  end
end
