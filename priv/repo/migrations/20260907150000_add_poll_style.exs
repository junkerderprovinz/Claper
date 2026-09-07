defmodule Claper.Repo.Migrations.AddPollStyle do
  use Ecto.Migration

  def change do
    # How a poll is drawn, which is the difference between a poll and a rating
    # scale. A scale IS a poll: the same question, the same options, the same
    # one vote each. What changes is that the options are ordered, so they are
    # laid out as a row from left to right and an average is worth printing.
    #
    # Giving it a column rather than a table of its own is the whole point.
    # Everything a poll already has, from the vote that stops somebody voting
    # twice to the CSV export, applies to a scale without being written again.
    alter table(:polls) do
      add :style, :string, default: "bars", null: false
    end
  end
end
