defmodule ClaperWeb.AddinController do
  @moduledoc """
  The small API the PowerPoint sidebar talks to.

  Every action works on the event the token resolved to, never on an id the
  caller supplies, so the token is the whole authorisation. The surface is kept
  to what the sidebar needs: the polls and quizzes of this event, creating and
  editing them, and issuing the read-only link a slide block reads.
  """

  use ClaperWeb, :controller

  alias Claper.Polls
  alias Claper.Quizzes

  @doc """
  The event behind the token and its polls, so the sidebar can show what exists
  and offer it for a slide.
  """
  def index(%{assigns: %{addin_event: event}} = conn, _params) do
    polls =
      event.presentation_file
      |> case do
        nil -> []
        file -> Polls.list_polls(file.id)
      end
      |> Enum.map(&poll_json/1)

    json(conn, %{
      event: %{
        name: event.name,
        code: event.code,
        # How many slides Claper itself holds. A poll positioned inside that
        # range belongs to the deck uploaded to Claper; one beyond it was made
        # for a slide of someone else's document. The sidebar shows the second
        # kind by default, because an event that has been used before otherwise
        # opens on a list of questions from a different talk.
        deck_length: deck_length(event)
      },
      polls: polls
    })
  end

  @doc """
  Creates a poll on this event from a title and a list of options.

  The position is taken from the end of the deck rather than from the caller:
  a poll made for a PowerPoint slide is selected by its id, not by a Claper
  position, and giving it a free position keeps it out of the way of polls the
  owner placed on the deck itself.
  """
  def create(%{assigns: %{addin_event: event}} = conn, params) do
    with {:ok, file} <- presentation_file(event),
         {:ok, title} <- fetch_title(params),
         {:ok, options} <- fetch_options(params) do
      attrs = %{
        "title" => title,
        "presentation_file_id" => file.id,
        "position" => next_position(file),
        "enabled" => true,
        "show_results" => Map.get(params, "show_results", true),
        "poll_opts" => Enum.map(options, &%{"content" => &1, "vote_count" => 0})
      }

      case Polls.create_poll(attrs) do
        {:ok, poll} -> conn |> put_status(:created) |> json(poll_json(poll))
        {:error, _changeset} -> error(conn, 422, "poll could not be created")
      end
    else
      {:error, status, message} -> error(conn, status, message)
    end
  end

  @doc """
  Renames a poll or replaces its options.

  The id is looked up inside the token's event, so a poll of another event is
  simply not found rather than refused with a different message.
  """
  def update(%{assigns: %{addin_event: event}} = conn, %{"id" => id} = params) do
    with {:ok, poll} <- find_poll(event, id),
         {:ok, attrs} <- update_attrs(params, poll) do
      case Polls.update_poll(event.uuid, poll, attrs) do
        {:ok, poll} -> json(conn, poll_json(Claper.Polls.get_poll!(poll.id)))
        {:error, _changeset} -> error(conn, 422, "poll could not be updated")
      end
    else
      {:error, status, message} -> error(conn, status, message)
    end
  end

  @doc """
  Deletes a poll of this event.
  """
  def delete(%{assigns: %{addin_event: event}} = conn, %{"id" => id}) do
    case find_poll(event, id) do
      {:ok, poll} ->
        Polls.delete_poll(event.uuid, poll)
        send_resp(conn, :no_content, "")

      {:error, status, message} ->
        error(conn, status, message)
    end
  end

  @doc """
  The quizzes of this event.
  """
  def quiz_index(%{assigns: %{addin_event: event}} = conn, _params) do
    quizzes =
      case event.presentation_file do
        nil -> []
        file -> Quizzes.list_quizzes(file.id)
      end

    json(conn, %{
      quizzes: Enum.map(quizzes, &quiz_json/1),
      event: %{deck_length: deck_length(event)}
    })
  end

  @doc """
  Creates a quiz on this event.

  Positioned past the deck for the same reason a poll made here is: it is
  selected by its id from a slide of another document, not by a Claper position.
  """
  def quiz_create(%{assigns: %{addin_event: event}} = conn, params) do
    with {:ok, file} <- presentation_file(event),
         {:ok, title} <- fetch_title(params),
         {:ok, questions} <- fetch_questions(params) do
      attrs = %{
        "title" => title,
        "presentation_file_id" => file.id,
        "position" => next_position(file),
        "enabled" => true,
        # False, unlike a poll: a quiz has a correct answer, and releasing it
        # while the room is still answering gives it away. The owner releases it
        # from the manage screen when the question is over.
        "show_results" => Map.get(params, "show_results", false),
        "quiz_questions" => questions
      }

      case Quizzes.create_quiz(attrs) do
        {:ok, quiz} ->
          conn |> put_status(:created) |> json(quiz_json(reload_quiz(quiz)))

        {:error, _changeset} ->
          error(conn, 422, "quiz could not be created")
      end
    else
      {:error, status, message} -> error(conn, status, message)
    end
  end

  @doc """
  Renames a quiz or replaces its questions.
  """
  def quiz_update(%{assigns: %{addin_event: event}} = conn, %{"id" => id} = params) do
    with {:ok, quiz} <- find_quiz(event, id),
         {:ok, attrs} <- quiz_update_attrs(params, quiz) do
      case Quizzes.update_quiz(event.uuid, quiz, attrs) do
        {:ok, quiz} -> json(conn, quiz_json(reload_quiz(quiz)))
        {:error, _changeset} -> error(conn, 422, "quiz could not be updated")
      end
    else
      {:error, status, message} -> error(conn, status, message)
    end
  end

  @doc """
  Deletes a quiz of this event.
  """
  def quiz_delete(%{assigns: %{addin_event: event}} = conn, %{"id" => id}) do
    case find_quiz(event, id) do
      {:ok, quiz} ->
        Quizzes.delete_quiz(event.uuid, quiz)
        send_resp(conn, :no_content, "")

      {:error, status, message} ->
        error(conn, status, message)
    end
  end

  @doc """
  Issues the read-only link a block on a slide reads, and returns it once.

  The sidebar keeps this in the document's own settings, so a deck asks for one
  link and reuses it. It is a different token from the one authenticating this
  call: that one writes and stays on this machine, this one only reads and is
  meant to travel inside the file.

  It leaves links the event already has alone, so a second presentation using
  the same event does not blank the blocks in the first one. Revoking from the
  manage screen still closes all of them at once.
  """
  def embed_token(%{assigns: %{addin_event: event}} = conn, _params) do
    case Claper.Events.create_presenter_embed_token_for_addin(event) do
      {:ok, token} -> conn |> put_status(:created) |> json(%{token: token})
      {:error, _} -> error(conn, 422, "link could not be created")
    end
  end

  defp deck_length(event), do: (event.presentation_file && event.presentation_file.length) || 0

  defp find_poll(event, id) do
    with {parsed, ""} <- Integer.parse(to_string(id)),
         poll when not is_nil(poll) <- Polls.get_poll_for_event(parsed, event.id) do
      {:ok, poll}
    else
      _ -> {:error, 404, "no such poll on this event"}
    end
  end

  defp update_attrs(params, poll) do
    title =
      case fetch_title(params) do
        {:ok, value} -> value
        _ -> poll.title
      end

    case params do
      %{"options" => _} ->
        with {:ok, options} <- fetch_options(params) do
          {:ok,
           %{
             "title" => title,
             "poll_opts" => Enum.map(options, &%{"content" => &1, "vote_count" => 0})
           }}
        end

      _ ->
        {:ok, %{"title" => title}}
    end
  end

  defp find_quiz(event, id) do
    with {parsed, ""} <- Integer.parse(to_string(id)),
         quiz when not is_nil(quiz) <-
           Quizzes.get_quiz_for_event(parsed, event.id, quiz_preload()) do
      {:ok, quiz}
    else
      _ -> {:error, 404, "no such quiz on this event"}
    end
  end

  defp quiz_preload, do: [:quiz_questions, quiz_questions: :quiz_question_opts]

  defp reload_quiz(quiz), do: Quizzes.get_quiz!(quiz.id, quiz_preload())

  defp quiz_update_attrs(params, quiz) do
    title =
      case fetch_title(params) do
        {:ok, value} -> value
        _ -> quiz.title
      end

    case params do
      %{"questions" => _} ->
        with {:ok, questions} <- fetch_questions(params) do
          {:ok, %{"title" => title, "quiz_questions" => questions}}
        end

      _ ->
        {:ok, %{"title" => title}}
    end
  end

  # Questions arrive as a list of {content, options}, each option {content,
  # correct}. Rebuilt rather than patched: the sidebar edits a whole quiz and
  # sends it back, and `on_replace: :delete` on the association makes that the
  # shape Ecto expects.
  defp fetch_questions(%{"questions" => questions}) when is_list(questions) do
    parsed = Enum.map(questions, &parse_question/1)

    cond do
      parsed == [] ->
        {:error, 422, "at least one question is required"}

      Enum.find(parsed, &match?({:error, _, _}, &1)) ->
        Enum.find(parsed, &match?({:error, _, _}, &1))

      true ->
        {:ok, Enum.map(parsed, fn {:ok, question} -> question end)}
    end
  end

  defp fetch_questions(_), do: {:error, 422, "questions must be a list"}

  defp parse_question(%{"content" => content, "options" => options})
       when is_binary(content) and is_list(options) do
    opts =
      options
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn opt ->
        %{
          "content" => opt |> Map.get("content", "") |> to_string() |> String.trim(),
          "is_correct" => opt |> Map.get("correct", false) |> truthy?()
        }
      end)
      |> Enum.reject(&(&1["content"] == ""))

    cond do
      String.trim(content) == "" ->
        {:error, 422, "every question needs a text"}

      length(opts) < 2 ->
        {:error, 422, "every question needs at least two answers"}

      not Enum.any?(opts, & &1["is_correct"]) ->
        {:error, 422, "every question needs at least one correct answer"}

      true ->
        {:ok, %{"content" => String.trim(content), "type" => "qcm", "quiz_question_opts" => opts}}
    end
  end

  defp parse_question(_), do: {:error, 422, "every question needs a text and answers"}

  # The sidebar sends JSON booleans, but a hand-written call may send the string
  # a form would. Anything else is false rather than an error: a wrong value here
  # can only ever mark an answer as not correct, which the changeset then catches.
  defp truthy?(value), do: value in [true, "true", "on", 1, "1"]

  defp presentation_file(%{presentation_file: nil}),
    do: {:error, 409, "this event has no presentation yet"}

  defp presentation_file(%{presentation_file: file}), do: {:ok, file}

  defp fetch_title(%{"title" => title}) when is_binary(title) do
    case String.trim(title) do
      "" -> {:error, 422, "title is required"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp fetch_title(_), do: {:error, 422, "title is required"}

  defp fetch_options(%{"options" => options}) when is_list(options) do
    cleaned =
      options
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if length(cleaned) >= 2,
      do: {:ok, cleaned},
      else: {:error, 422, "at least two options are required"}
  end

  defp fetch_options(_), do: {:error, 422, "options must be a list"}

  # Past the end of the deck, so it never collides with a poll the owner placed
  # on a slide of the presentation Claper itself stores.
  defp next_position(file), do: (file.length || 0) + 1

  defp poll_json(poll) do
    %{
      id: poll.id,
      title: poll.title,
      position: poll.position,
      enabled: poll.enabled,
      show_results: poll.show_results,
      options:
        Enum.map(poll.poll_opts || [], fn opt ->
          %{id: opt.id, content: opt.content, votes: opt.vote_count}
        end)
    }
  end

  defp quiz_json(quiz) do
    %{
      id: quiz.id,
      title: quiz.title,
      position: quiz.position,
      enabled: quiz.enabled,
      show_results: quiz.show_results,
      questions:
        Enum.map(quiz.quiz_questions || [], fn question ->
          %{
            id: question.id,
            content: question.content,
            options:
              Enum.map(question.quiz_question_opts || [], fn opt ->
                %{
                  id: opt.id,
                  content: opt.content,
                  correct: opt.is_correct,
                  responses: opt.response_count
                }
              end)
          }
        end)
    }
  end

  defp error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end
end
