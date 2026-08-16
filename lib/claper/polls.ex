defmodule Claper.Polls do
  @moduledoc """
  The Polls context.
  """

  import Ecto.Query, warn: false
  alias Claper.Repo

  alias Claper.Polls.Poll
  alias Claper.Polls.PollOpt
  alias Claper.Polls.PollVote

  @doc """
  Returns the list of polls for a given presentation file.

  ## Examples

      iex> list_polls(123)
      [%Poll{}, ...]

  """
  def list_polls(presentation_file_id) do
    from(p in Poll,
      where: p.presentation_file_id == ^presentation_file_id,
      order_by: [asc: p.id, asc: p.position]
    )
    |> Repo.all()
    |> Repo.preload([:poll_opts])
  end

  @doc """
  Returns the list of polls for a given presentation file and a given position.

  ## Examples

      iex> list_polls_at_position(123, 0)
      [%Poll{}, ...]

  """
  def list_polls_at_position(presentation_file_id, position) do
    from(p in Poll,
      where: p.presentation_file_id == ^presentation_file_id and p.position == ^position,
      order_by: [asc: p.id]
    )
    |> Repo.all()
    |> Repo.preload([:poll_opts])
  end

  @doc """
  Gets a single poll and set percentages for each poll options.

  Raises `Ecto.NoResultsError` if the Poll does not exist.

  ## Examples

      iex> get_poll!(123)
      %Poll{}

      iex> get_poll!(456)
      ** (Ecto.NoResultsError)

  """
  def get_poll!(id),
    do:
      Repo.get!(Poll, id)
      |> Repo.preload(
        poll_opts:
          from(
            o in PollOpt,
            order_by: [asc: o.id]
          )
      )
      |> set_percentages()

  @doc """
  Gets a single poll scoped to the given event.

  Returns `nil` if the poll does not exist or does not belong to the event.
  """
  def get_poll_for_event(id, event_id) do
    from(p in Poll,
      join: pf in assoc(p, :presentation_file),
      where: p.id == ^id and pf.event_id == ^event_id
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      poll ->
        poll
        |> Repo.preload(
          poll_opts:
            from(
              o in PollOpt,
              order_by: [asc: o.id]
            )
        )
        |> set_percentages()
    end
  end

  @doc """
  Gets a single poll for a given position.

  ## Examples

      iex> get_poll!(123, 0)
      %Poll{}

  """
  def get_poll_current_position(presentation_file_id, position) do
    from(p in Poll,
      where:
        p.position == ^position and p.presentation_file_id == ^presentation_file_id and
          p.enabled == true
    )
    |> Repo.one()
    |> Repo.preload(
      poll_opts:
        from(
          o in PollOpt,
          order_by: [asc: o.id]
        )
    )
    |> set_percentages()
  end

  @doc """
  Calculate percentage of all poll options for a given poll.

  ## Examples

      iex> set_percentages(poll)
      %Poll{}

  """
  def set_percentages(%Poll{poll_opts: poll_opts} = poll) when is_list(poll_opts) do
    total = Enum.map(poll.poll_opts, fn e -> e.vote_count end) |> Enum.sum()

    %{
      poll
      | poll_opts:
          poll.poll_opts
          |> Enum.map(fn o -> %{o | percentage: calculate_percentage(o, total)} end)
    }
  end

  def set_percentages(poll), do: poll

  defp calculate_percentage(opt, total) do
    if total > 0,
      do: Float.round(opt.vote_count / total * 100) |> :erlang.float_to_binary(decimals: 0),
      else: 0
  end

  @doc """
  Creates a poll.

  ## Examples

      iex> create_poll(%{field: value})
      {:ok, %Poll{}}

      iex> create_poll(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_poll(attrs \\ %{}) do
    %Poll{}
    |> Poll.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, poll} ->
        poll = Repo.preload(poll, presentation_file: :event)
        broadcast({:ok, poll, poll.presentation_file.event.uuid}, :poll_created)

      {:error, changeset} ->
        {:error, %{changeset | action: :insert}}
    end
  end

  @doc """
  Updates a poll.

  ## Examples

      iex> update_poll("123e4567-e89b-12d3-a456-426614174000", poll, %{field: new_value})
      {:ok, %Poll{}}

      iex> update_poll("123e4567-e89b-12d3-a456-426614174000", poll, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_poll(event_uuid, %Poll{} = poll, attrs) do
    poll
    |> Poll.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, poll} ->
        broadcast({:ok, poll, event_uuid}, :poll_updated)

      {:error, changeset} ->
        {:error, %{changeset | action: :update}}
    end
  end

  @doc """
  Deletes a poll.

  ## Examples

      iex> delete_poll("123e4567-e89b-12d3-a456-426614174000", poll)
      {:ok, %Poll{}}

      iex> delete_poll("123e4567-e89b-12d3-a456-426614174000", poll)
      {:error, %Ecto.Changeset{}}

  """
  def delete_poll(event_uuid, %Poll{} = poll) do
    {:ok, poll} = Repo.delete(poll)
    broadcast({:ok, poll, event_uuid}, :poll_deleted)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking poll changes.

  ## Examples

      iex> change_poll(poll)
      %Ecto.Changeset{data: %Poll{}}

  """
  def change_poll(%Poll{} = poll, attrs \\ %{}) do
    Poll.changeset(poll, attrs)
  end

  @doc """
  Add an empty poll opt to a poll changeset.
  """
  def add_poll_opt(changeset) do
    changeset
    |> Ecto.Changeset.put_assoc(
      :poll_opts,
      Ecto.Changeset.get_field(changeset, :poll_opts) ++ [%PollOpt{}]
    )
  end

  @doc """
  Remove a poll opt from a poll changeset.
  """
  def remove_poll_opt(changeset, poll_opt) do
    changeset
    |> Ecto.Changeset.put_assoc(
      :poll_opts,
      Ecto.Changeset.get_field(changeset, :poll_opts) -- [poll_opt]
    )
  end

  def vote(user_id, event_uuid, poll_opts, poll_id)
      when is_number(user_id) and is_list(poll_opts) do
    case Enum.reduce(poll_opts, Ecto.Multi.new(), fn opt, multi ->
           Ecto.Multi.update(
             multi,
             {:update_poll_opt, opt.id},
             PollOpt.changeset(opt, %{"vote_count" => opt.vote_count + 1})
           )
           |> Ecto.Multi.insert(
             {:insert_poll_vote, opt.id},
             PollVote.changeset(%PollVote{}, %{
               user_id: user_id,
               poll_opt_id: opt.id,
               poll_id: poll_id
             })
           )
         end)
         |> Repo.transaction() do
      {:ok, _} ->
        poll = get_poll!(poll_id)
        broadcast({:ok, poll, event_uuid}, :poll_updated)
    end
  end

  def vote(attendee_identifier, event_uuid, poll_opts, poll_id) when is_list(poll_opts) do
    case Enum.reduce(poll_opts, Ecto.Multi.new(), fn opt, multi ->
           Ecto.Multi.update(
             multi,
             {:update_poll_opt, opt.id},
             PollOpt.changeset(opt, %{"vote_count" => opt.vote_count + 1})
           )
           |> Ecto.Multi.insert(
             {:insert_poll_vote, opt.id},
             PollVote.changeset(%PollVote{}, %{
               attendee_identifier: attendee_identifier,
               poll_opt_id: opt.id,
               poll_id: poll_id
             })
           )
         end)
         |> Repo.transaction() do
      {:ok, _} ->
        poll = get_poll!(poll_id)
        broadcast({:ok, poll, event_uuid}, :poll_updated)
    end
  end

  @doc """
  Submits a rating for a slider poll: matches the value against an existing
  poll_opt of this poll (a slider poll keeps one poll_opt per distinct value,
  its content being the value itself, e.g. "7") and increments its vote_count,
  or creates a new poll_opt if nobody picked that value yet. Also records a
  PollVote the same way a regular choice vote does, so "have I already voted"
  (Polls.get_poll_vote/2) works identically for both poll types.

  Returns `{:error, :out_of_range}` when the value is not a whole number
  inside the poll's own `min_value`..`max_value` range.

  ## Examples

      iex> submit_rating(attendee_identifier, event_uuid, poll_id, "7")
      {:ok, %Poll{}}

      iex> submit_rating(attendee_identifier, event_uuid, poll_id, "42")
      {:error, :out_of_range}

  """
  def submit_rating(identifier, event_uuid, poll_id, value) do
    with {:ok, rating} <- cast_rating(get_poll!(poll_id), value),
         {:ok, _poll_opt} <- record_rating(identifier, poll_id, rating) do
      broadcast({:ok, get_poll!(poll_id), event_uuid}, :poll_updated)
    end
  end

  defp record_rating(identifier, poll_id, rating) do
    Repo.transaction(fn ->
      with {:ok, poll_opt} <- rated_poll_opt(poll_id, rating),
           {:ok, _vote} <- insert_rating_vote(identifier, poll_id, poll_opt) do
        poll_opt
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp rated_poll_opt(poll_id, rating) do
    case find_rated_poll_opt(poll_id, rating) do
      nil ->
        %PollOpt{}
        |> PollOpt.changeset(%{
          content: Integer.to_string(rating),
          vote_count: 1,
          poll_id: poll_id
        })
        |> Repo.insert()

      opt ->
        opt
        |> PollOpt.changeset(%{vote_count: opt.vote_count + 1})
        |> Repo.update()
    end
  end

  defp insert_rating_vote(identifier, poll_id, poll_opt) do
    vote_attrs = %{poll_opt_id: poll_opt.id, poll_id: poll_id}

    vote_attrs =
      if is_number(identifier),
        do: Map.put(vote_attrs, :user_id, identifier),
        else: Map.put(vote_attrs, :attendee_identifier, identifier)

    %PollVote{} |> PollVote.changeset(vote_attrs) |> Repo.insert()
  end

  defp cast_rating(%Poll{} = poll, value) when is_binary(value) do
    case Integer.parse(value) do
      {rating, ""} -> cast_rating(poll, rating)
      _ -> {:error, :out_of_range}
    end
  end

  defp cast_rating(%Poll{min_value: min, max_value: max}, value)
       when is_integer(value) and value >= min and value <= max,
       do: {:ok, value}

  defp cast_rating(_poll, _value), do: {:error, :out_of_range}

  defp find_rated_poll_opt(poll_id, rating) do
    content = Integer.to_string(rating)

    from(o in PollOpt, where: o.poll_id == ^poll_id and o.content == ^content)
    |> Repo.one()
  end

  @doc """
  Average of every rating submitted to a slider poll, rounded to one decimal.
  Returns `nil` while nobody has rated yet, so callers can tell "no votes"
  apart from a genuine average of 0.

  ## Examples

      iex> average_rating(poll)
      7.4

  """
  def average_rating(%Poll{poll_opts: poll_opts}) when is_list(poll_opts) do
    {sum, count} =
      Enum.reduce(poll_opts, {0, 0}, fn opt, {sum, count} ->
        case Integer.parse(opt.content) do
          {value, _rest} -> {sum + value * opt.vote_count, count + opt.vote_count}
          :error -> {sum, count}
        end
      end)

    if count > 0, do: Float.round(sum / count, 1), else: nil
  end

  def average_rating(_poll), do: nil

  @doc """
  Vote spread of a slider poll, one entry per value of its range -- values
  nobody picked included, so the graph keeps the shape of the scale. The
  `percentage` is relative to the most picked value, not to the total, so the
  tallest bar always fills its container.

  ## Examples

      iex> rating_distribution(poll)
      [%{value: 1, vote_count: 0, percentage: 0}, %{value: 2, vote_count: 4, percentage: 100}]

  """
  def rating_distribution(%Poll{poll_opts: poll_opts} = poll) when is_list(poll_opts) do
    counts =
      Enum.reduce(poll_opts, %{}, fn opt, acc ->
        case Integer.parse(opt.content) do
          {value, _rest} -> Map.update(acc, value, opt.vote_count, &(&1 + opt.vote_count))
          :error -> acc
        end
      end)

    highest = counts |> Map.values() |> Enum.max(fn -> 0 end)

    Enum.map(poll.min_value..poll.max_value, fn value ->
      vote_count = Map.get(counts, value, 0)

      %{
        value: value,
        vote_count: vote_count,
        percentage: if(highest > 0, do: round(vote_count / highest * 100), else: 0)
      }
    end)
  end

  def rating_distribution(_poll), do: []

  @doc """
  Middle of a slider poll's range, where the slider starts before the attendee
  moves it.

  ## Examples

      iex> default_rating(poll)
      5

  """
  def default_rating(%Poll{min_value: min, max_value: max})
      when is_integer(min) and is_integer(max),
      do: div(min + max, 2)

  def default_rating(_poll), do: 0

  def disable_all(presentation_file_id, position) do
    from(p in Poll,
      where: p.presentation_file_id == ^presentation_file_id and p.position == ^position
    )
    |> Repo.update_all(set: [enabled: false])
  end

  def set_enabled(id) do
    get_poll!(id)
    |> Ecto.Changeset.change(enabled: true)
    |> Repo.update()
  end

  def set_disabled(id) do
    get_poll!(id)
    |> Ecto.Changeset.change(enabled: false)
    |> Repo.update()
  end

  defp broadcast({:ok, poll, event_uuid}, event) do
    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{event_uuid}",
      {event, poll}
    )

    {:ok, poll}
  end

  @doc """
  Gets a all poll_vote.


  ## Examples

      iex> get_poll_vote!(321, 123)
      [%PollVote{}]

  """
  def get_poll_vote(user_id, poll_id) when is_number(user_id) do
    from(p in PollVote,
      where: p.poll_id == ^poll_id and p.user_id == ^user_id,
      order_by: [asc: p.id]
    )
    |> Repo.all()
  end

  def get_poll_vote(attendee_identifier, poll_id) do
    from(p in PollVote,
      where: p.poll_id == ^poll_id and p.attendee_identifier == ^attendee_identifier,
      order_by: [asc: p.id]
    )
    |> Repo.all()
  end

  @doc """
  Creates a poll_vote.

  ## Examples

      iex> create_poll_vote(%{field: value})
      {:ok, %PollVote{}}

      iex> create_poll_vote(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_poll_vote(attrs \\ %{}) do
    %PollVote{}
    |> PollVote.changeset(attrs)
    |> Repo.insert()
  end
end
