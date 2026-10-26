defmodule Claper.Polls.PollVote do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          attendee_identifier: String.t() | nil,
          rank: integer() | nil,
          points: integer() | nil,
          x: float() | nil,
          y: float() | nil,
          poll_id: integer() | nil,
          poll_opt_id: integer() | nil,
          user_id: integer() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "poll_votes" do
    field :attendee_identifier, :string
    # Where this person put the option when asked to order them, counted from
    # one. Null for a poll and a scale, where a vote is a choice, not a place.
    field :rank, :integer

    # What this person spent on the option, for a points poll.
    field :points, :integer

    # Where on the picture this person tapped, as a fraction of the width and
    # the height. Fractions rather than pixels: the picture is drawn at whatever
    # size the slide or the phone gives it, and a pixel on one means nothing on
    # the other.
    field :x, :float
    field :y, :float

    belongs_to :poll, Claper.Polls.Poll
    belongs_to :poll_opt, Claper.Polls.PollOpt
    belongs_to :user, Claper.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(poll_vote, attrs) do
    poll_vote
    |> cast(attrs, [
      :attendee_identifier,
      :user_id,
      :poll_opt_id,
      :poll_id,
      :rank,
      :points,
      :x,
      :y
    ])
    |> validate_required([:poll_opt_id, :poll_id])
    |> validate_number(:points, greater_than_or_equal_to: 0)
    # A tap outside the picture is not a tap on it. The numbers come from a
    # browser and are the one thing here a person can hand-edit, so they are
    # checked rather than trusted.
    |> validate_number(:x, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:y, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end
