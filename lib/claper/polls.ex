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

  @doc """
  Records an order somebody put the options in, best first.

  A ranking is one row per option rather than one row per person, each carrying
  the place it was given. That is what lets the result be an average place, and
  it is why this does not go through `vote/4`: there an answer is a choice, here
  it is a position, and every option gets one.

  Nothing is counted into `vote_count`. A ranking has no winner by frequency,
  and a count that says "everyone picked all of them" is a number without a
  meaning.

  ## Examples

      iex> rank("abc123", event_uuid, [opt_b, opt_a], poll_id)
      {:ok, %Poll{}}

  """
  def rank(who, event_uuid, ordered_opts, poll_id) when is_list(ordered_opts) do
    ordered_opts = Enum.uniq_by(ordered_opts, & &1.id)

    multi =
      ordered_opts
      |> Enum.with_index(1)
      |> Enum.reduce(Ecto.Multi.new(), fn {opt, place}, multi ->
        attrs = %{
          poll_opt_id: opt.id,
          poll_id: poll_id,
          rank: place
        }

        attrs =
          if is_number(who),
            do: Map.put(attrs, :user_id, who),
            else: Map.put(attrs, :attendee_identifier, who)

        Ecto.Multi.insert(
          multi,
          {:insert_rank, opt.id},
          PollVote.changeset(%PollVote{}, attrs)
        )
      end)

    case Repo.transaction(multi) do
      {:ok, _} ->
        poll = get_poll!(poll_id)
        broadcast({:ok, poll, event_uuid}, :poll_updated)

      {:error, _, changeset, _} ->
        {:error, changeset}
    end
  end

  @doc """
  Spends a budget across the options, one row per option that got something.

  `spent` is `%{poll_opt_id => points}`. Options given nothing are not written
  at all: a zero carries no information and one row per option per person is
  what a hundred-point poll in a full room would otherwise cost.

  `vote_count` is deliberately left alone, the way `rank/4` leaves it alone.
  Adding points into it would make the ordinary bar rendering come out right by
  accident and make the number beside the bar a lie: it counts people, and
  points are not people. The result is read back out of the rows instead, with
  `Poll.spent/2`.
  """
  def allocate(who, event_uuid, spent, poll_id) when is_map(spent) do
    multi =
      spent
      |> Enum.filter(fn {_opt_id, points} -> is_integer(points) and points > 0 end)
      |> Enum.reduce(Ecto.Multi.new(), fn {opt_id, points}, multi ->
        attrs = %{
          poll_opt_id: opt_id,
          poll_id: poll_id,
          points: points
        }

        attrs =
          if is_number(who),
            do: Map.put(attrs, :user_id, who),
            else: Map.put(attrs, :attendee_identifier, who)

        Ecto.Multi.insert(
          multi,
          {:insert_points, opt_id},
          PollVote.changeset(%PollVote{}, attrs)
        )
      end)

    case Repo.transaction(multi) do
      {:ok, _} ->
        poll = get_poll!(poll_id)
        broadcast({:ok, poll, event_uuid}, :poll_updated)

      {:error, _, changeset, _} ->
        {:error, changeset}
    end
  end

  @doc """
  Records one tap on the picture, as fractions of its width and height.

  A pins poll has exactly one option, created with it, so the vote still hangs
  off an option the way every other vote does and nothing downstream has to
  learn about a vote without one.
  """
  def pin(who, event_uuid, {x, y}, poll_id) do
    poll = get_poll!(poll_id)

    case poll.poll_opts do
      [opt | _] ->
        attrs = %{poll_opt_id: opt.id, poll_id: poll_id, x: x, y: y}

        attrs =
          if is_number(who),
            do: Map.put(attrs, :user_id, who),
            else: Map.put(attrs, :attendee_identifier, who)

        case %PollVote{} |> PollVote.changeset(attrs) |> Repo.insert() do
          {:ok, _vote} -> broadcast({:ok, get_poll!(poll_id), event_uuid}, :poll_updated)
          {:error, changeset} -> {:error, changeset}
        end

      _ ->
        {:error, :no_option}
    end
  end

  @doc """
  Every vote cast on one poll, which for a ranking is every place given.

  Read as a whole rather than aggregated in the database: the result is an
  average place per option, and the poll is on a slide that redraws whenever
  somebody answers, so the rows are wanted anyway.
  """
  def list_poll_votes(poll_id) do
    from(v in PollVote, where: v.poll_id == ^poll_id) |> Repo.all()
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
