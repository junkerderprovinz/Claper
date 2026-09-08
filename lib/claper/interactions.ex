defmodule Claper.Interactions do
  alias Claper.Polls
  alias Claper.Forms
  alias Claper.Embeds
  alias Claper.Events
  alias Claper.Presentations
  alias Claper.Quizzes
  import Ecto.Query, warn: false

  @type interaction :: Polls.Poll | Forms.Form | Embeds.Embed

  def get_number_total_interactions(presentation_file_id) do
    from(p in Polls.Poll,
      where: p.presentation_file_id == ^presentation_file_id,
      select: count(p.id)
    )
    |> Claper.Repo.one()
    |> Kernel.+(
      from(f in Forms.Form,
        where: f.presentation_file_id == ^presentation_file_id,
        select: count(f.id)
      )
      |> Claper.Repo.one()
    )
    |> Kernel.+(
      from(e in Embeds.Embed,
        where: e.presentation_file_id == ^presentation_file_id,
        select: count(e.id)
      )
      |> Claper.Repo.one()
    )
    |> Kernel.+(
      from(q in Quizzes.Quiz,
        where: q.presentation_file_id == ^presentation_file_id,
        select: count(q.id)
      )
      |> Claper.Repo.one()
    )
  end

  @doc """
  Every enabled question in the whole deck, in slide order.

  For a room answering at its own pace rather than following the presenter.
  Ordered by the slide the question sits on, because that is the order the
  author wrote them in and the only order a reader would expect; questions
  sharing a slide keep the order they were created in, the same tie-break the
  per-slide list already uses.

  Embeds are left out on purpose. An embed is a web page put on a slide for the
  room to look at, not a question with an answer, so a list of things still to
  answer is the wrong place for it.
  """
  def list_enabled_interactions(%Events.Event{
        presentation_file: %Presentations.PresentationFile{id: presentation_file_id}
      }) do
    polls = Polls.list_polls(presentation_file_id)
    forms = Forms.list_forms(presentation_file_id)
    quizzes = Quizzes.list_quizzes(presentation_file_id)

    (polls ++ forms ++ quizzes)
    |> Enum.filter(&(&1.enabled == true))
    |> Enum.sort_by(&{&1.position, &1.inserted_at}, :asc)
  end

  def list_enabled_interactions(_event), do: []

  def get_active_interaction(event, position) do
    with {:ok, interactions} <- get_interactions_at_position(event, position) do
      interactions |> Enum.filter(&(&1.enabled == true)) |> List.first()
    end
  end

  def get_interactions_at_position(
        %Events.Event{
          presentation_file: %Presentations.PresentationFile{id: presentation_file_id}
        } = event,
        position,
        broadcast \\ false
      ) do
    with polls <- Polls.list_polls_at_position(presentation_file_id, position),
         forms <- Forms.list_forms_at_position(presentation_file_id, position),
         embeds <- Embeds.list_embeds_at_position(presentation_file_id, position),
         quizzes <- Quizzes.list_quizzes_at_position(presentation_file_id, position) do
      interactions =
        (polls ++ forms ++ embeds ++ quizzes)
        |> Enum.sort_by(& &1.inserted_at, {:asc, NaiveDateTime})

      if broadcast do
        active_interaction = interactions |> Enum.filter(&(&1.enabled == true)) |> List.first()

        Phoenix.PubSub.broadcast(
          Claper.PubSub,
          "event:#{event.uuid}",
          {:current_interaction, active_interaction}
        )
      end

      {:ok, interactions}
    end
  end

  @doc """
  Moves an interaction to another slide position.

  The interaction is disabled when moved so it doesn't stay live on a slide
  the audience is not looking at. Returns `{:ok, interaction}` (a no-op when
  the position is unchanged) or `{:error, :invalid_position}`.
  """
  def move_interaction(
        %Events.Event{
          presentation_file: %Presentations.PresentationFile{} = presentation_file
        } = event,
        interaction,
        to
      )
      when is_integer(to) do
    count = presentation_file.length || 0

    cond do
      to < 0 or to >= count -> {:error, :invalid_position}
      to == interaction.position -> {:ok, interaction}
      true -> do_move_interaction(event.uuid, interaction, to)
    end
  end

  defp do_move_interaction(event_uuid, %Polls.Poll{} = poll, to),
    do: Polls.update_poll(event_uuid, poll, %{position: to, enabled: false})

  defp do_move_interaction(event_uuid, %Forms.Form{} = form, to),
    do: Forms.update_form(event_uuid, form, %{position: to, enabled: false})

  defp do_move_interaction(event_uuid, %Embeds.Embed{} = embed, to),
    do: Embeds.update_embed(event_uuid, embed, %{position: to, enabled: false})

  # Quiz.changeset requires quiz_questions via cast_assoc, so they must be
  # loaded even though the move doesn't touch them.
  defp do_move_interaction(event_uuid, %Quizzes.Quiz{} = quiz, to) do
    quiz = Claper.Repo.preload(quiz, quiz_questions: :quiz_question_opts)
    Quizzes.update_quiz(event_uuid, quiz, %{position: to, enabled: false})
  end

  def enable_interaction(interaction) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:disable_polls, fn _repo, _ ->
      {count, _} = Polls.disable_all(interaction.presentation_file_id, interaction.position)
      {:ok, count}
    end)
    |> Ecto.Multi.run(:disable_forms, fn _repo, _ ->
      {count, _} = Forms.disable_all(interaction.presentation_file_id, interaction.position)
      {:ok, count}
    end)
    |> Ecto.Multi.run(:disable_embeds, fn _repo, _ ->
      {count, _} = Embeds.disable_all(interaction.presentation_file_id, interaction.position)
      {:ok, count}
    end)
    |> Ecto.Multi.run(:disable_quizzes, fn _repo, _ ->
      {count, _} = Quizzes.disable_all(interaction.presentation_file_id, interaction.position)
      {:ok, count}
    end)
    |> Ecto.Multi.run(:enable_interaction, fn _repo, _ ->
      set_enabled(interaction)
    end)
    |> Claper.Repo.transaction()
    |> case do
      {:ok, _} -> :ok
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp set_enabled(%Polls.Poll{} = interaction) do
    Polls.set_enabled(interaction.id)
  end

  defp set_enabled(%Forms.Form{} = interaction) do
    Forms.set_enabled(interaction.id)
  end

  defp set_enabled(%Embeds.Embed{} = interaction) do
    Embeds.set_enabled(interaction.id)
  end

  defp set_enabled(%Quizzes.Quiz{} = interaction) do
    Quizzes.set_enabled(interaction.id)
  end

  def disable_interaction(%Polls.Poll{} = interaction) do
    Polls.set_disabled(interaction.id)
  end

  def disable_interaction(%Forms.Form{} = interaction) do
    Forms.set_disabled(interaction.id)
  end

  def disable_interaction(%Embeds.Embed{} = interaction) do
    Embeds.set_disabled(interaction.id)
  end

  def disable_interaction(%Quizzes.Quiz{} = interaction) do
    Quizzes.set_disabled(interaction.id)
  end
end
