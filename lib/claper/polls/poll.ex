defmodule Claper.Polls.Poll do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          title: String.t(),
          position: integer() | nil,
          total: integer() | nil,
          enabled: boolean() | nil,
          multiple: boolean() | nil,
          presentation_file_id: integer() | nil,
          poll_opts: [Claper.Polls.PollOpt.t()],
          poll_votes: [Claper.Polls.PollVote.t()] | nil,
          show_results: boolean() | nil,
          style: String.t() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @derive {Jason.Encoder, only: [:title, :position]}
  schema "polls" do
    field :title, :string
    field :position, :integer
    field :total, :integer, virtual: true
    field :enabled, :boolean
    field :multiple, :boolean
    field :show_results, :boolean
    # "bars", "scale" or "ranking". All three ask one question with the same
    # options; what differs is what an answer is. A poll picks one, a scale
    # picks a place on an ordered row, and a ranking puts every option in an
    # order of its own.
    field :style, :string, default: "bars"

    belongs_to :presentation_file, Claper.Presentations.PresentationFile

    has_many :poll_opts, Claper.Polls.PollOpt,
      preload_order: [asc: :id],
      on_replace: :delete

    has_many :poll_votes, Claper.Polls.PollVote, on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(poll, attrs) do
    poll
    |> cast(attrs, [
      :title,
      :presentation_file_id,
      :position,
      :enabled,
      :total,
      :multiple,
      :show_results,
      :style
    ])
    |> cast_assoc(:poll_opts, required: true)
    |> validate_required([:title, :presentation_file_id, :position])
    |> validate_length(:title, max: 255)
    |> validate_inclusion(:style, ~w(bars scale ranking))
    |> forbid_multiple_where_it_makes_no_sense()
  end

  # Ticking three boxes on a scale from one to five is not a rating, and the
  # average underneath would be arithmetic on nothing. A ranking already uses
  # every option, so "several answers" says nothing there either. Refused
  # rather than quietly ignored, so the contradiction is visible where it was
  # made.
  defp forbid_multiple_where_it_makes_no_sense(changeset) do
    style = get_field(changeset, :style)

    cond do
      not get_field(changeset, :multiple) -> changeset
      style == "scale" -> add_error(changeset, :multiple, "a scale takes one answer")
      style == "ranking" -> add_error(changeset, :multiple, "a ranking uses every answer")
      true -> changeset
    end
  end

  @doc """
  What the room said on average, or nil while nobody has answered.

  The value of an option is where it sits in the row, counted from one, which
  is what lets a scale be labelled "never" to "always" and still average to
  3.4. Only meaningful for a scale, which is why it is not on every poll.
  """
  def average(%__MODULE__{style: "scale", poll_opts: opts}) when is_list(opts) do
    {sum, votes} =
      opts
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0}, fn {opt, value}, {sum, votes} ->
        {sum + value * (opt.vote_count || 0), votes + (opt.vote_count || 0)}
      end)

    if votes > 0, do: Float.round(sum / votes, 1), else: nil
  end

  def average(_poll), do: nil

  @doc """
  The options of a ranking in the order the room put them, best first.

  Each answer is a place from one upward, so the option with the lowest average
  place is the one most people put at the top. That is the whole result of a
  ranking: not how often something was picked, but where it landed.

  `votes` are the rows of `poll_votes` for this poll, each carrying a `rank`.
  An option nobody ranked keeps its place at the end rather than being dropped,
  because an option missing from the slide reads as a mistake.
  """
  def ranked(%__MODULE__{poll_opts: opts}, votes) when is_list(opts) and is_list(votes) do
    places =
      votes
      |> Enum.filter(&(&1.rank && &1.poll_opt_id))
      |> Enum.group_by(& &1.poll_opt_id, & &1.rank)

    opts
    |> Enum.map(fn opt ->
      case Map.get(places, opt.id) do
        nil -> {opt, nil}
        ranks -> {opt, Float.round(Enum.sum(ranks) / length(ranks), 2)}
      end
    end)
    # Unranked last, and among the ranked the lowest average first. The option's
    # own id breaks a tie, so the order does not shuffle between updates.
    |> Enum.sort_by(fn {opt, place} -> {is_nil(place), place || 0, opt.id} end)
  end

  def ranked(_poll, _votes), do: []
end
