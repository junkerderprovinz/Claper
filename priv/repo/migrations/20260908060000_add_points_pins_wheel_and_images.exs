defmodule Claper.Repo.Migrations.AddPointsPinsWheelAndImages do
  use Ecto.Migration

  @moduledoc """
  Four more shapes a poll can take, and the one column each of them needs.

  They share a table on purpose. All four ask one question with the same
  options and differ only in what an answer is: a choice, a place in an order,
  a number of points, or a spot on a picture. Splitting them into four tables
  would mean four copies of the release machinery, the enabled flag, the
  position on the slide and every query that walks a presentation's questions.
  """

  def change do
    alter table(:polls) do
      # How many points a person has to spend on a points poll. Per poll rather
      # than a fixed hundred: ten points is a different question from a hundred,
      # and the difference is the author's to make.
      add :points_budget, :integer, default: 100

      # The picture a pin poll is answered on. A path under the same uploads
      # directory the slides live in, so it is served, backed up and deleted
      # with everything else.
      add :image, :string
    end

    alter table(:poll_opts) do
      # An option can carry a picture beside its wording. Beside, not instead:
      # a picture with no words cannot be read out, cannot be searched and
      # cannot be answered by somebody using a screen reader.
      add :image, :string
    end

    alter table(:poll_votes) do
      # What this person spent on this option. Null for every other shape.
      add :points, :integer

      # Where on the picture this person tapped, as a fraction of the width and
      # the height rather than pixels: the picture is drawn at whatever size the
      # slide or the phone gives it, and a pixel measured on one is meaningless
      # on the other.
      add :x, :float
      add :y, :float
    end

    alter table(:presentation_states) do
      # Which option the wheel last landed on. In the state rather than in a
      # message, so somebody who joins after the spin sees the result instead of
      # an empty wheel.
      add :wheel_opt_id, :integer
    end

    alter table(:events) do
      # Whether the room answers at its own pace instead of following the
      # presenter. Off by default: the ordinary case is a talk, and a
      # questionnaire that opens itself during one would show every question at
      # once.
      add :self_paced, :boolean, default: false, null: false
    end
  end
end
