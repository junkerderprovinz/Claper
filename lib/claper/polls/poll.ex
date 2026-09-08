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
          points_budget: integer() | nil,
          image: String.t() | nil,
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
    # All of these ask one question with the same options; what differs is what
    # an answer is. A poll picks one, a scale picks a place on an ordered row, a
    # ranking puts every option in an order of its own, a points poll spends a
    # budget across them, a pins poll answers by tapping a picture, and a wheel
    # is not answered at all - it is spun.
    field :style, :string, default: "bars"

    # How many points there are to spend, for a points poll.
    field :points_budget, :integer, default: 100

    # The picture a pins poll is answered on.
    field :image, :string

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
      :style,
      :points_budget,
      :image
    ])
    |> cast_assoc(:poll_opts, required: true)
    |> validate_required([:title, :presentation_file_id, :position])
    |> validate_length(:title, max: 255)
    |> validate_inclusion(:style, ~w(bars scale ranking points pins wheel))
    |> validate_number(:points_budget, greater_than: 0, less_than_or_equal_to: 1000)
    |> require_a_picture_to_pin_on()
    |> forbid_multiple_where_it_makes_no_sense()
  end

  # A pins poll with no picture is a question with nothing to answer on. Caught
  # here rather than left to the slide, where it would be an empty rectangle
  # with no explanation in front of a room.
  defp require_a_picture_to_pin_on(changeset) do
    if get_field(changeset, :style) == "pins" and blank?(get_field(changeset, :image)) do
      add_error(changeset, :image, "a pins poll needs a picture to pin on")
    else
      changeset
    end
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

  # Ticking three boxes on a scale from one to five is not a rating, and the
  # average underneath would be arithmetic on nothing. A ranking already uses
  # every option, so "several answers" says nothing there either. Refused
  # rather than quietly ignored, so the contradiction is visible where it was
  # made.
  defp forbid_multiple_where_it_makes_no_sense(changeset) do
    style = get_field(changeset, :style)
    # Compared rather than negated: the field is nil on a poll that never set
    # it, and `not nil` raises in Elixir. The earlier version got away with it
    # because `and` short-circuits, so the nil was only ever reached on a scale,
    # where it is always set. A cond evaluates it every time.
    multiple = get_field(changeset, :multiple) == true

    cond do
      not multiple -> changeset
      style == "scale" -> add_error(changeset, :multiple, "a scale takes one answer")
      style == "ranking" -> add_error(changeset, :multiple, "a ranking uses every answer")
      style == "points" -> add_error(changeset, :multiple, "a points poll spends on every answer")
      style == "pins" -> add_error(changeset, :multiple, "a pins poll is answered on the picture")
      style == "wheel" -> add_error(changeset, :multiple, "a wheel is spun, not answered")
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

  @doc """
  What the room spent on each option, most first, with the share of the total.

  The result of a points poll is not how many people picked something but how
  much of a limited budget the room was willing to put behind it. That is the
  whole reason to ask this way rather than with a poll: it forces a trade-off
  where ticking boxes does not.

  An option nobody spent on keeps its place at the end with zero, because an
  option missing from the slide reads as a mistake.
  """
  def spent(%__MODULE__{poll_opts: opts}, votes) when is_list(opts) and is_list(votes) do
    by_opt =
      votes
      |> Enum.filter(&(&1.points && &1.poll_opt_id))
      |> Enum.group_by(& &1.poll_opt_id, & &1.points)
      |> Map.new(fn {opt_id, points} -> {opt_id, Enum.sum(points)} end)

    total = by_opt |> Map.values() |> Enum.sum()

    opts
    |> Enum.map(fn opt ->
      points = Map.get(by_opt, opt.id, 0)
      share = if total > 0, do: Float.round(points * 100 / total, 1), else: 0.0
      {opt, points, share}
    end)
    # Most points first, and the option's own id breaks a tie so the order does
    # not shuffle between updates while the room is reading it.
    |> Enum.sort_by(fn {opt, points, _share} -> {-points, opt.id} end)
  end

  def spent(_poll, _votes), do: []

  @doc """
  Every tap on the picture, as `{x, y}` fractions of its width and height.

  Fractions, because the picture is drawn at one size on a slide and another on
  a phone, and a pixel measured on one means nothing on the other. Whoever
  draws them multiplies by the size they have.
  """
  def pins(votes) when is_list(votes) do
    votes
    |> Enum.filter(&(&1.x && &1.y))
    |> Enum.map(&{&1.x, &1.y})
  end

  def pins(_votes), do: []

  @doc """
  Whether this shape is answered by the room at all.

  A wheel is not: it has options and it is shown on a slide like the others,
  but it is spun by the presenter and nobody votes. Anything that offers a way
  to answer has to ask this first, or the room gets a button that does nothing.
  """
  def answerable?(%__MODULE__{style: "wheel"}), do: false
  def answerable?(%__MODULE__{}), do: true
end
