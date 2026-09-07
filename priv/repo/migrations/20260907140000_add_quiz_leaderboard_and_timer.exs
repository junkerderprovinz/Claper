defmodule Claper.Repo.Migrations.AddQuizLeaderboardAndTimer do
  use Ecto.Migration

  def change do
    # What to call somebody on a leaderboard. Claper knows an attendee only by
    # an opaque identifier, and "attendee f3a91c scored 4" is a row nobody in
    # the room can find themselves in. The name is the one they already give
    # the chat, carried onto the answer so a board can be drawn without asking
    # for it twice. Nullable, because an event may be answered anonymously and
    # every response written before this existed has none.
    alter table(:quiz_responses) do
      add :name, :string
    end

    # How long the room has per question, in seconds. Null means no limit,
    # which is what every quiz had until now and stays the default.
    alter table(:quizzes) do
      add :seconds_per_question, :integer
    end

    # No index here: the board reads every response of one quiz and groups
    # them, and quiz_responses(quiz_id) has been indexed since the table was
    # created.
  end
end
