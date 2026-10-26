defmodule Claper.QuizzesTest do
  use Claper.DataCase

  alias Claper.Quizzes
  alias Claper.Quizzes.Quiz

  import Claper.QuizzesFixtures
  import Claper.PresentationsFixtures
  import Claper.AccountsFixtures

  describe "quizzes" do
    test "list_quizzes/1 returns all quizzes for a presentation file" do
      presentation_file = presentation_file_fixture()
      quiz = quiz_fixture(%{presentation_file: presentation_file})
      assert Quizzes.list_quizzes(presentation_file.id) == [quiz]
    end

    test "list_quizzes_at_position/2 returns quizzes at specific position" do
      presentation_file = presentation_file_fixture()
      quiz = quiz_fixture(%{presentation_file: presentation_file, position: 1})

      assert Quizzes.list_quizzes_at_position(presentation_file.id, 1) == [quiz]
      assert Quizzes.list_quizzes_at_position(presentation_file.id, 2) == []
    end

    test "get_quiz!/1 returns the quiz with given id" do
      quiz = quiz_fixture()
      fetched_quiz = Quizzes.get_quiz!(quiz.id, quiz_questions: :quiz_question_opts)

      # Compare all fields except the virtual percentage field in quiz_question_opts
      assert Map.drop(fetched_quiz, [:quiz_questions]) == Map.drop(quiz, [:quiz_questions])
      assert length(fetched_quiz.quiz_questions) == length(quiz.quiz_questions)

      Enum.zip(fetched_quiz.quiz_questions, quiz.quiz_questions)
      |> Enum.each(fn {fetched_question, original_question} ->
        assert Map.drop(fetched_question, [:quiz_question_opts]) ==
                 Map.drop(original_question, [:quiz_question_opts])

        assert length(fetched_question.quiz_question_opts) ==
                 length(original_question.quiz_question_opts)

        Enum.zip(fetched_question.quiz_question_opts, original_question.quiz_question_opts)
        |> Enum.each(fn {fetched_opt, original_opt} ->
          assert Map.drop(fetched_opt, [:percentage]) == Map.drop(original_opt, [:percentage])
        end)
      end)
    end

    test "create_quiz/1 with valid data creates a quiz" do
      presentation_file = presentation_file_fixture()

      valid_attrs = %{
        title: "Test Quiz",
        position: 1,
        presentation_file_id: presentation_file.id,
        quiz_questions: [
          %{
            content: "Test Question",
            type: "qcm",
            quiz_question_opts: [
              %{content: "Option 1", is_correct: true},
              %{content: "Option 2", is_correct: false}
            ]
          }
        ]
      }

      assert {:ok, %Quiz{} = quiz} = Quizzes.create_quiz(valid_attrs)
      assert quiz.title == "Test Quiz"
      assert quiz.position == 1
      assert length(quiz.quiz_questions) == 1
      assert length(List.first(quiz.quiz_questions).quiz_question_opts) == 2
    end

    test "create_quiz/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Quizzes.create_quiz(%{})
    end

    test "update_quiz/3 with valid data updates the quiz" do
      quiz = quiz_fixture()
      event_uuid = Ecto.UUID.generate()
      update_attrs = %{title: "Updated Title"}

      assert {:ok, %Quiz{} = updated_quiz} =
               Quizzes.update_quiz(event_uuid, quiz, update_attrs)

      assert updated_quiz.title == "Updated Title"
    end

    test "delete_quiz/2 deletes the quiz" do
      quiz = quiz_fixture()
      event_uuid = Ecto.UUID.generate()
      assert {:ok, %Quiz{}} = Quizzes.delete_quiz(event_uuid, quiz)
      assert_raise Ecto.NoResultsError, fn -> Quizzes.get_quiz!(quiz.id) end
    end

    test "change_quiz/2 returns a quiz changeset" do
      quiz = quiz_fixture()
      assert %Ecto.Changeset{} = Quizzes.change_quiz(quiz)
    end

    test "add_quiz_question/1 adds a new question with default options" do
      quiz = quiz_fixture()
      changeset = Quizzes.change_quiz(quiz)
      updated_changeset = Quizzes.add_quiz_question(changeset)

      questions = Ecto.Changeset.get_field(updated_changeset, :quiz_questions)
      # Original + new question
      assert length(questions) == 2

      new_question = List.last(questions)
      # Two default options
      assert length(new_question.quiz_question_opts) == 2
    end

    test "submit_quiz/4 with user records responses and updates counts" do
      quiz = quiz_fixture()
      user = user_fixture()
      event_uuid = Ecto.UUID.generate()
      question = List.first(quiz.quiz_questions)
      option = List.first(question.quiz_question_opts)

      assert {:ok, updated_quiz} =
               Quizzes.submit_quiz(user, event_uuid, [option], quiz.id)

      updated_option =
        updated_quiz.quiz_questions
        |> List.first()
        |> Map.get(:quiz_question_opts)
        |> List.first()

      assert updated_option.response_count == 1
    end

    test "submit_quiz/4 with attendee_identifier records responses" do
      quiz = quiz_fixture()
      event_uuid = Ecto.UUID.generate()
      question = List.first(quiz.quiz_questions)
      option = List.first(question.quiz_question_opts)
      attendee_id = "test-attendee"

      assert {:ok, _updated_quiz} =
               Quizzes.submit_quiz(attendee_id, event_uuid, [option], quiz.id)

      responses = Quizzes.get_quiz_responses(attendee_id, quiz.id)
      assert length(responses) == 1
    end

    test "calculate_user_score/2 correctly calculates score" do
      quiz = quiz_fixture()
      user = user_fixture()
      question = List.first(quiz.quiz_questions)
      correct_option = Enum.find(question.quiz_question_opts, & &1.is_correct)

      # Submit correct answer
      {:ok, _} = Quizzes.submit_quiz(user, Ecto.UUID.generate(), [correct_option], quiz.id)
      assert {1, 1} = Quizzes.calculate_user_score(user.id, quiz.id)
    end

    test "disable_all/2 disables all quizzes at position" do
      presentation_file = presentation_file_fixture()
      quiz = quiz_fixture(%{presentation_file: presentation_file, position: 1, enabled: true})

      Quizzes.disable_all(presentation_file.id, 1)
      updated_quiz = Quizzes.get_quiz!(quiz.id)
      refute updated_quiz.enabled
    end

    test "set_enabled/1 enables a quiz" do
      quiz = quiz_fixture(%{enabled: false})
      assert {:ok, updated_quiz} = Quizzes.set_enabled(quiz.id)
      assert updated_quiz.enabled
    end

    test "set_disabled/1 disables a quiz" do
      quiz = quiz_fixture(%{enabled: true})
      assert {:ok, updated_quiz} = Quizzes.set_disabled(quiz.id)
      refute updated_quiz.enabled
    end

    test "submit_quiz/4 with duplicate opts deduplicates by id" do
      quiz = quiz_fixture()
      event_uuid = Ecto.UUID.generate()
      question = List.first(quiz.quiz_questions)
      option = List.first(question.quiz_question_opts)
      attendee_id = "test-attendee-dedup"

      # Simulate the bug: same opt appears twice (e.g. due to stale struct comparison)
      duplicate_opts = [option, %{option | response_count: option.response_count + 1}]

      assert {:ok, _updated_quiz} =
               Quizzes.submit_quiz(attendee_id, event_uuid, duplicate_opts, quiz.id)

      # Should only create one response despite duplicate opts
      responses = Quizzes.get_quiz_responses(attendee_id, quiz.id)
      assert length(responses) == 1
    end

    test "get_quiz_for_event/3 returns quiz when it belongs to the event" do
      presentation_file = presentation_file_fixture()
      quiz = quiz_fixture(%{presentation_file: presentation_file})

      fetched_quiz = Quizzes.get_quiz_for_event(quiz.id, presentation_file.event_id)
      assert fetched_quiz.id == quiz.id
    end

    test "get_quiz_for_event/3 returns nil when quiz belongs to a different event" do
      presentation_file_a = presentation_file_fixture()
      presentation_file_b = presentation_file_fixture()
      quiz = quiz_fixture(%{presentation_file: presentation_file_a})

      assert is_nil(Quizzes.get_quiz_for_event(quiz.id, presentation_file_b.event_id))
    end

    test "get_quiz_for_event/3 returns nil for nonexistent quiz id" do
      presentation_file = presentation_file_fixture()
      assert is_nil(Quizzes.get_quiz_for_event(-1, presentation_file.event_id))
    end

    test "submit_quiz/4 with user and duplicate opts deduplicates by id" do
      quiz = quiz_fixture()
      user = user_fixture()
      event_uuid = Ecto.UUID.generate()
      question = List.first(quiz.quiz_questions)
      option = List.first(question.quiz_question_opts)

      # Simulate the bug: same opt appears twice with different response_count
      duplicate_opts = [option, %{option | response_count: option.response_count + 1}]

      assert {:ok, _updated_quiz} =
               Quizzes.submit_quiz(user, event_uuid, duplicate_opts, quiz.id)
    end
  end

  # A quiz told the room an average and nothing else, which is the one number
  # nobody in it is interested in. This is the other thing a quiz is for.
  describe "leaderboard/2" do
    setup do
      quiz = quiz_fixture()
      question = List.first(quiz.quiz_questions)
      [right, wrong] = question.quiz_question_opts

      %{quiz: quiz, right: right, wrong: wrong, uuid: Ecto.UUID.generate()}
    end

    test "an unanswered quiz has an empty board", %{quiz: quiz} do
      assert Quizzes.leaderboard(quiz.id) == []
    end

    test "counts right answers per person, not per response", %{
      quiz: quiz,
      right: right,
      wrong: wrong,
      uuid: uuid
    } do
      Quizzes.submit_quiz("ada", uuid, [right], quiz.id, "Ada")
      Quizzes.submit_quiz("grace", uuid, [wrong], quiz.id, "Grace")

      assert [{"Ada", 1, 1, _}, {"Grace", 0, 1, _}] = Quizzes.leaderboard(quiz.id)
    end

    # The identifier is opaque on purpose, so a row carrying it is a row nobody
    # in the room can claim. Better to leave it off the wall.
    test "somebody who never gave a name is left off the board", %{
      quiz: quiz,
      right: right,
      uuid: uuid
    } do
      Quizzes.submit_quiz("anonymous", uuid, [right], quiz.id, nil)
      Quizzes.submit_quiz("named", uuid, [right], quiz.id, "Ada")

      assert [{"Ada", 1, 1, _}] = Quizzes.leaderboard(quiz.id)
    end

    test "the board is capped, so a full room does not fill the slide", %{
      quiz: quiz,
      right: right,
      uuid: uuid
    } do
      for n <- 1..15 do
        Quizzes.submit_quiz("person#{n}", uuid, [right], quiz.id, "Person #{n}")
      end

      assert length(Quizzes.leaderboard(quiz.id)) == 10
      assert length(Quizzes.leaderboard(quiz.id, 3)) == 3
    end

    # Answering quickly has to be worth something, or the board is alphabetical
    # luck among everyone who got it right.
    test "equal scores are ordered by who finished first", %{
      quiz: quiz,
      right: right,
      uuid: uuid
    } do
      Quizzes.submit_quiz("first", uuid, [right], quiz.id, "First")
      # The stamps have a one second resolution, so the second answer needs to
      # land in a later second for the order to mean anything.
      Process.sleep(1100)
      Quizzes.submit_quiz("second", uuid, [right], quiz.id, "Second")

      assert [{"First", _, _, _}, {"Second", _, _, _}] = Quizzes.leaderboard(quiz.id)
    end

    test "a logged in person is named from their account", %{quiz: quiz, right: right, uuid: uuid} do
      user = user_fixture(%{first_name: "Alan", last_name: "Turing"})

      Quizzes.submit_quiz(user, uuid, [right], quiz.id)

      assert [{"Alan Turing", 1, 1, _}] = Quizzes.leaderboard(quiz.id)
    end
  end

  # Null means no clock, which is what every quiz had before there was one.
  describe "the question timer" do
    test "a quiz has no time limit unless it is given one" do
      assert quiz_fixture().seconds_per_question == nil
    end

    test "a limit is kept" do
      quiz = quiz_fixture(%{seconds_per_question: 30})
      assert Quizzes.get_quiz!(quiz.id).seconds_per_question == 30
    end

    # Refused rather than clamped: an author who typed a wrong number is told,
    # instead of quietly given a different one.
    test "five seconds is not a question and an hour is not a timer" do
      assert {:error, _} =
               Quizzes.update_quiz(
                 Ecto.UUID.generate(),
                 quiz_fixture(),
                 %{"seconds_per_question" => 2}
               )

      assert {:error, _} =
               Quizzes.update_quiz(
                 Ecto.UUID.generate(),
                 quiz_fixture(),
                 %{"seconds_per_question" => 4000}
               )
    end
  end
end
