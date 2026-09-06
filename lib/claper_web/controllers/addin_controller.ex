defmodule ClaperWeb.AddinController do
  @moduledoc """
  The small API the PowerPoint sidebar talks to.

  Every action works on the event the token resolved to, never on an id the
  caller supplies, so the token is the whole authorisation. The surface is kept
  to what the sidebar needs: list the polls of this event, and create one.
  """

  use ClaperWeb, :controller

  alias Claper.Polls

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
        # for a slide of someone else's document, and the sidebar says so
        # instead of showing one flat list.
        deck_length: (event.presentation_file && event.presentation_file.length) || 0
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

  defp error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end
end
