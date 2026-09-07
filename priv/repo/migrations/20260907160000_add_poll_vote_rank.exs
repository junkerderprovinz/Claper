defmodule Claper.Repo.Migrations.AddPollVoteRank do
  use Ecto.Migration

  def change do
    # Where somebody put this option when they were asked to order them, counted
    # from one. Null for a poll and for a scale, where a vote is a choice rather
    # than a position.
    #
    # A ranking fits into poll_votes rather than a table of its own because the
    # unique index that once allowed one vote per person was already dropped for
    # multiple-choice polls: several rows per person are the shape the table
    # takes now. A ranking is one row per option, each carrying its place.
    alter table(:poll_votes) do
      add :rank, :integer
    end
  end
end
