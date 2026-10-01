defmodule ClaperWeb.AddinController do
  @moduledoc """
  JSON API for the PowerPoint sidebar.

  Actions work on the event resolved from the caller's key, and every poll,
  quiz or form id is looked up within that event.
  """

  use ClaperWeb, :controller

  alias Claper.Forms
  alias Claper.Polls
  alias Claper.Quizzes

  @doc """
  Tells the sidebar whether it holds an event key or a personal key.
  """
  def me(%{assigns: %{addin_event: event}} = conn, _params) do
    json(conn, %{kind: "event", event: %{name: event.name, code: event.code}})
  end

  def me(%{assigns: %{addin_user: user}} = conn, _params) do
    json(conn, %{kind: "account", user: %{email: user.email}})
  end

  @doc """
  Lists the user's events that have not expired, newest first. Requires a
  personal key.
  """
  def event_index(%{assigns: %{addin_user: user}} = conn, _params) do
    events =
      user.id
      |> Claper.Events.list_events()
      |> Enum.reject(&expired?/1)
      |> Enum.map(&%{name: &1.name, code: &1.code})

    json(conn, %{events: events})
  end

  def event_index(conn, _params),
    do: error(conn, 403, "a personal key is needed to list events")

  @doc """
  Creates an event with a generated code. Requires a personal key.
  """
  def event_create(%{assigns: %{addin_user: user}} = conn, params) do
    with {:ok, name} <- fetch_title(params, "name"),
         {:ok, event} <- create_event_with_free_code(user, name) do
      conn |> put_status(:created) |> json(%{event: %{name: event.name, code: event.code}})
    else
      {:error, status, message} -> error(conn, status, message)
      _ -> error(conn, 422, "event could not be created")
    end
  end

  def event_create(conn, _params),
    do: error(conn, 403, "a personal key is needed to create an event")

  @doc """
  Returns the event and its polls.
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
        # Lets the sidebar tell interactions it created (positioned past the
        # deck) from those placed on the uploaded presentation.
        deck_length: deck_length(event)
      },
      polls: polls
    })
  end

  @doc """
  Creates a poll from a title and a list of options, positioned after the last
  slide of the event's presentation.
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
  Returns the quizzes of the event.
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
  Creates a quiz, positioned after the last slide like `create/2`.
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
        # Results would reveal the correct answer, so they stay hidden until the
        # presenter releases them.
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
  Returns the forms of the event, which the sidebar calls open questions.
  """
  def form_index(%{assigns: %{addin_event: event}} = conn, _params) do
    forms =
      case event.presentation_file do
        nil -> []
        file -> Forms.list_forms(file.id)
      end

    json(conn, %{
      forms: Enum.map(forms, &form_json/1),
      event: %{deck_length: deck_length(event)}
    })
  end

  @doc """
  Creates a form, positioned after the last slide like `create/2`.
  """
  def form_create(%{assigns: %{addin_event: event}} = conn, params) do
    with {:ok, file} <- presentation_file(event),
         {:ok, title} <- fetch_title(params),
         {:ok, fields} <- fetch_fields(params) do
      attrs = %{
        "title" => title,
        "presentation_file_id" => file.id,
        "position" => next_position(file),
        "enabled" => true,
        "fields" => fields
      }

      case Forms.create_form(attrs) do
        {:ok, form} -> conn |> put_status(:created) |> json(form_json(form))
        {:error, _changeset} -> error(conn, 422, "form could not be created")
      end
    else
      {:error, status, message} -> error(conn, status, message)
    end
  end

  @doc """
  Renames a form or replaces its fields.
  """
  def form_update(%{assigns: %{addin_event: event}} = conn, %{"id" => id} = params) do
    with {:ok, form} <- find_form(event, id),
         {:ok, attrs} <- form_update_attrs(params, form) do
      case Forms.update_form(event.uuid, form, attrs) do
        {:ok, form} -> json(conn, form_json(form))
        {:error, _changeset} -> error(conn, 422, "form could not be updated")
      end
    else
      {:error, status, message} -> error(conn, status, message)
    end
  end

  @doc """
  Deletes a form of this event.
  """
  def form_delete(%{assigns: %{addin_event: event}} = conn, %{"id" => id}) do
    case find_form(event, id) do
      {:ok, form} ->
        Forms.delete_form(event.uuid, form)
        send_resp(conn, :no_content, "")

      {:error, status, message} ->
        error(conn, status, message)
    end
  end

  @doc """
  Creates a read-only embed token for the slide blocks of a deck. Existing
  tokens of the event stay valid.
  """
  def embed_token(%{assigns: %{addin_event: event}} = conn, _params) do
    case Claper.Events.create_presenter_embed_token_for_addin(event) do
      {:ok, token} -> conn |> put_status(:created) |> json(%{token: token})
      {:error, _} -> error(conn, 422, "link could not be created")
    end
  end

  defp expired?(%{expired_at: nil}), do: false

  defp expired?(%{expired_at: at}), do: NaiveDateTime.compare(at, NaiveDateTime.utc_now()) != :gt

  defp create_event_with_free_code(user, name, attempts \\ 5)

  defp create_event_with_free_code(_user, _name, 0),
    do: {:error, 503, "could not find a free code, try again"}

  defp create_event_with_free_code(user, name, attempts) do
    attrs = %{
      "name" => name,
      "code" => random_code(),
      "user_id" => user.id,
      "started_at" => NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }

    case Claper.Events.create_event(attrs) do
      {:ok, event} ->
        {:ok, event}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :code),
          do: create_event_with_free_code(user, name, attempts - 1),
          else: {:error, 422, "event could not be created"}

      _ ->
        {:error, 422, "event could not be created"}
    end
  end

  defp random_code do
    1..5
    |> Enum.map(fn _ -> Enum.random(?a..?z) end)
    |> List.to_string()
  end

  defp deck_length(event), do: (event.presentation_file && event.presentation_file.length) || 0

  @doc """
  Builds a slide showing the chosen interaction from the deck the caller sends.
  See `Claper.Addin.SlideBuilder`.
  """
  def slide(%{assigns: %{addin_event: event}} = conn, params) do
    with {:ok, choice} <- fetch_choice(event, params),
         {:ok, deck} <- fetch_deck(params),
         {:ok, built} <- build_slide(deck, choice, params["onto"]) do
      json(conn, %{slide: Base.encode64(built)})
    else
      {:error, :no_such_slide} ->
        error(conn, 422, "that slide is not in the presentation")

      {:error, :no_block} ->
        error(
          conn,
          409,
          "put one Claper block on a slide first, every slide after that is copied from it"
        )

      {:error, :not_a_presentation} ->
        error(conn, 422, "that was not a presentation")

      {:error, status, message} ->
        error(conn, status, message)

      _ ->
        error(conn, 422, "the slide could not be built")
    end
  end

  defp build_slide(deck, choice, nil), do: Claper.Addin.SlideBuilder.one_slide(deck, choice)

  defp build_slide(deck, choice, onto) do
    case Integer.parse(to_string(onto)) do
      {position, ""} when position >= 1 ->
        Claper.Addin.SlideBuilder.onto_slide(deck, choice, position)

      _ ->
        {:error, :no_such_slide}
    end
  end

  # The id must belong to this event, since it ends up in a shared file.
  defp fetch_choice(event, %{"kind" => "poll", "id" => id}) do
    with {:ok, poll} <- find_poll(event, id), do: {:ok, %{"kind" => "poll", "id" => poll.id}}
  end

  defp fetch_choice(event, %{"kind" => "quiz", "id" => id}) do
    with {:ok, quiz} <- find_quiz(event, id), do: {:ok, %{"kind" => "quiz", "id" => quiz.id}}
  end

  defp fetch_choice(event, %{"kind" => "form", "id" => id}) do
    with {:ok, form} <- find_form(event, id), do: {:ok, %{"kind" => "form", "id" => form.id}}
  end

  defp fetch_choice(_event, %{"kind" => kind}) when kind in ~w(join messages),
    do: {:ok, %{"kind" => kind}}

  defp fetch_choice(_event, _params), do: {:error, 422, "say what the slide should show"}

  defp fetch_deck(%{"deck" => deck}) when is_binary(deck) do
    case Base.decode64(deck) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, 422, "the presentation could not be read"}
    end
  end

  defp fetch_deck(_params), do: {:error, 422, "send the presentation to copy a slide from"}

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

  defp find_form(event, id) do
    with {parsed, ""} <- Integer.parse(to_string(id)),
         form when not is_nil(form) <- Forms.get_form_for_event(parsed, event.id) do
      {:ok, form}
    else
      _ -> {:error, 404, "no such open question on this event"}
    end
  end

  defp form_update_attrs(params, form) do
    title =
      case fetch_title(params) do
        {:ok, value} -> value
        _ -> form.title
      end

    case params do
      %{"fields" => _} ->
        with {:ok, fields} <- fetch_fields(params) do
          {:ok, %{"title" => title, "fields" => fields}}
        end

      _ ->
        {:ok, %{"title" => title}}
    end
  end

  # A bare string is shorthand for a required text field with that name.
  defp fetch_fields(%{"fields" => fields}) when is_list(fields) do
    cleaned =
      fields
      |> Enum.map(&parse_field/1)
      |> Enum.reject(&is_nil/1)

    if cleaned == [],
      do: {:error, 422, "at least one box is required"},
      else: {:ok, cleaned}
  end

  defp fetch_fields(_), do: {:error, 422, "fields must be a list"}

  defp parse_field(name) when is_binary(name), do: parse_field(%{"name" => name})

  defp parse_field(%{"name" => name} = field) when is_binary(name) do
    case String.trim(name) do
      "" ->
        nil

      trimmed ->
        %{
          "name" => trimmed,
          # The attendee view renders only these two types.
          "type" => if(Map.get(field, "type") == "email", do: "email", else: "text"),
          "required" => Map.get(field, "required", true) |> truthy?()
        }
    end
  end

  defp parse_field(_), do: nil

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

  # The sidebar always sends the whole quiz, and the association replaces the
  # questions with `on_replace: :delete`.
  defp fetch_questions(%{"questions" => questions}) when is_list(questions) do
    parsed = Enum.map(questions, &parse_question/1)

    case {parsed, Enum.find(parsed, &match?({:error, _, _}, &1))} do
      {[], _} -> {:error, 422, "at least one question is required"}
      {_, nil} -> {:ok, Enum.map(parsed, fn {:ok, question} -> question end)}
      {_, error} -> error
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

  defp truthy?(value), do: value in [true, "true", "on", 1, "1"]

  defp presentation_file(%{presentation_file: nil}),
    do: {:error, 409, "this event has no presentation yet"}

  defp presentation_file(%{presentation_file: file}), do: {:ok, file}

  defp fetch_title(params, key \\ "title")

  defp fetch_title(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, 422, "#{key} is required"}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, 422, "#{key} is required"}
    end
  end

  defp fetch_title(_params, key), do: {:error, 422, "#{key} is required"}

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

  # Past the last slide, so it does not collide with interactions placed on the
  # uploaded presentation.
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

  defp form_json(form) do
    %{
      id: form.id,
      title: form.title,
      position: form.position,
      enabled: form.enabled,
      fields:
        Enum.map(form.fields || [], fn field ->
          %{name: field.name, type: field.type, required: field.required}
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
