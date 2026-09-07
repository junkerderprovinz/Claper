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
    # "bars" or "scale". A scale is the same poll drawn as an ordered row, with
    # an average underneath, which is what turns "pick one of five" into
    # "rate this from one to five".
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
    |> validate_inclusion(:style, ~w(bars scale))
    |> forbid_multiple_on_a_scale()
  end

  # Ticking three boxes on a scale from one to five is not a rating, and the
  # average underneath would be arithmetic on nothing. Refused rather than
  # quietly ignored, so the contradiction is visible where it was made.
  defp forbid_multiple_on_a_scale(changeset) do
    if get_field(changeset, :style) == "scale" and get_field(changeset, :multiple) do
      add_error(changeset, :multiple, "a scale takes one answer")
    else
      changeset
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
end
