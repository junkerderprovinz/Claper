defmodule Claper.PollsTest do
  use Claper.DataCase

  alias Claper.Polls

  describe "polls" do
    alias Claper.Polls.Poll

    import Claper.{PollsFixtures, PresentationsFixtures}

    @invalid_attrs %{title: nil}

    test "list_polls/1 returns all polls from a presentation" do
      presentation_file = presentation_file_fixture()
      poll = poll_fixture(%{presentation_file_id: presentation_file.id})

      polls = Polls.list_polls(presentation_file.id)
      assert [%Poll{} | _] = polls
      assert length(polls) == 1
      assert hd(polls).id == poll.id
    end

    test "list_polls_at_position/2 returns all polls from a presentation at a given position" do
      presentation_file = presentation_file_fixture()
      poll = poll_fixture(%{presentation_file_id: presentation_file.id, position: 5})

      polls = Polls.list_polls_at_position(presentation_file.id, 5)
      assert [%Poll{} | _] = polls
      assert length(polls) == 1
      assert hd(polls).id == poll.id
      assert hd(polls).position == 5
    end

    test "get_poll!/1 returns the poll with given id" do
      presentation_file = presentation_file_fixture()

      poll =
        poll_fixture(%{presentation_file_id: presentation_file.id})
        |> Claper.Polls.set_percentages()

      fetched_poll = Polls.get_poll!(poll.id)

      assert fetched_poll.id == poll.id
      assert fetched_poll.position == poll.position
      assert fetched_poll.poll_opts == poll.poll_opts
      assert fetched_poll.title == poll.title
    end

    test "create_poll/1 with valid data creates a poll" do
      presentation_file = presentation_file_fixture()

      valid_attrs = %{
        title: "some title",
        presentation_file_id: presentation_file.id,
        position: 0,
        poll_opts: [
          %{content: "some option 1", vote_count: 0},
          %{content: "some option 2", vote_count: 0}
        ]
      }

      assert {:ok, %Poll{} = poll} = Polls.create_poll(valid_attrs)
      assert poll.title == "some title"
    end

    test "create_poll/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Polls.create_poll(@invalid_attrs)
    end

    test "update_poll/3 with valid data updates the poll" do
      presentation_file = presentation_file_fixture()
      poll = poll_fixture(%{presentation_file_id: presentation_file.id})
      update_attrs = %{title: "some updated title"}

      assert {:ok, %Poll{} = poll} =
               Polls.update_poll(presentation_file.event_id, poll, update_attrs)

      assert poll.title == "some updated title"
    end

    test "update_poll/3 with invalid data returns error changeset" do
      presentation_file = presentation_file_fixture()
      poll = poll_fixture(%{presentation_file_id: presentation_file.id})

      assert {:error, %Ecto.Changeset{}} =
               Polls.update_poll(presentation_file.event_id, poll, @invalid_attrs)

      fetched_poll = Polls.get_poll!(poll.id)
      poll = poll |> Claper.Polls.set_percentages()

      assert fetched_poll.poll_opts == poll.poll_opts
      assert fetched_poll.poll_votes == poll.poll_votes
      assert fetched_poll.title == poll.title
    end

    test "delete_poll/2 deletes the poll" do
      presentation_file = presentation_file_fixture()
      poll = poll_fixture(%{presentation_file_id: presentation_file.id})

      assert {:ok, %Poll{}} = Polls.delete_poll(presentation_file.event_id, poll)
      assert_raise Ecto.NoResultsError, fn -> Polls.get_poll!(poll.id) end
    end

    test "change_poll/1 returns a poll changeset" do
      presentation_file = presentation_file_fixture()
      poll = poll_fixture(%{presentation_file_id: presentation_file.id})
      assert %Ecto.Changeset{} = Polls.change_poll(poll)
    end

    test "get_poll_for_event/2 returns poll when it belongs to the event" do
      presentation_file = presentation_file_fixture()
      poll = poll_fixture(%{presentation_file_id: presentation_file.id})

      fetched_poll = Polls.get_poll_for_event(poll.id, presentation_file.event_id)
      assert fetched_poll.id == poll.id
    end

    test "get_poll_for_event/2 returns nil when poll belongs to a different event" do
      presentation_file_a = presentation_file_fixture()
      presentation_file_b = presentation_file_fixture()
      poll = poll_fixture(%{presentation_file_id: presentation_file_a.id})

      assert is_nil(Polls.get_poll_for_event(poll.id, presentation_file_b.event_id))
    end

    test "get_poll_for_event/2 returns nil for nonexistent poll id" do
      presentation_file = presentation_file_fixture()
      assert is_nil(Polls.get_poll_for_event(-1, presentation_file.event_id))
    end
  end

  describe "poll_opts" do
    import Claper.{PollsFixtures, PresentationsFixtures}

    test "add_poll_opt/1 returns poll changeset plus the added poll_opt" do
      presentation_file = presentation_file_fixture()
      poll = poll_fixture(%{presentation_file_id: presentation_file.id})
      poll_changeset = poll |> Polls.change_poll()

      assert Ecto.Changeset.get_field(Polls.add_poll_opt(poll_changeset), :poll_opts)
             |> Enum.count() == 3
    end

    test "remove_poll_opt/2 returns poll changeset minus the removed poll_opt" do
      presentation_file = presentation_file_fixture()
      poll = poll_fixture(%{presentation_file_id: presentation_file.id})
      poll_changeset = poll |> Polls.change_poll()

      assert Ecto.Changeset.get_field(
               Polls.remove_poll_opt(poll_changeset, Enum.at(poll.poll_opts, 0)),
               :poll_opts
             )
             |> Enum.count() == 1
    end
  end

  describe "poll_votes" do
    import Claper.{PollsFixtures, PresentationsFixtures}

    test "get_poll_vote/2 returns the poll_vote with given id and user id" do
      poll_vote = poll_vote_fixture()
      assert Polls.get_poll_vote(poll_vote.user_id, poll_vote.poll_id) == [poll_vote]
    end

    test "vote/4 with valid data creates a poll_vote" do
      presentation_file = presentation_file_fixture(%{}, [:event])
      poll = poll_fixture(%{presentation_file_id: presentation_file.id})
      [poll_opt | _] = poll.poll_opts

      assert {:ok, %Polls.Poll{}} =
               Polls.vote(
                 presentation_file.event.user_id,
                 presentation_file.event_id,
                 [poll_opt],
                 poll.id
               )
    end
  end

  # A scale IS a poll: the same question, the same options, the same one vote
  # each. What changes is that the options are ordered, so they are drawn as a
  # row and an average is worth printing. Giving it a column rather than a
  # table of its own is what lets everything a poll already has apply to it.
  describe "a poll drawn as a scale" do
    import Claper.{PollsFixtures, PresentationsFixtures}

    alias Claper.Polls.Poll

    defp scale(votes) do
      file = presentation_file_fixture()

      {:ok, poll} =
        Polls.create_poll(%{
          "title" => "how much do you agree",
          "presentation_file_id" => file.id,
          "position" => 1,
          "style" => "scale",
          "poll_opts" =>
            Enum.map(votes, fn {label, count} -> %{"content" => label, "vote_count" => count} end)
        })

      Polls.get_poll!(poll.id)
    end

    test "a poll is bars unless it is asked to be a scale" do
      assert poll_fixture().style == "bars"
    end

    test "the average is the position in the row, so labels can be words" do
      poll = scale([{"never", 1}, {"sometimes", 0}, {"always", 1}])

      assert Poll.average(poll) == 2.0
    end

    test "nobody having answered is not an average of zero" do
      assert Poll.average(scale([{"never", 0}, {"always", 0}])) == nil
    end

    test "a poll drawn as bars has no average to print" do
      assert Poll.average(poll_fixture()) == nil
    end

    # Ticking three boxes on a scale from one to five is not a rating, and the
    # average underneath would be arithmetic on nothing.
    test "a scale cannot also take several answers" do
      file = presentation_file_fixture()

      assert {:error, changeset} =
               Polls.create_poll(%{
                 "title" => "both at once",
                 "presentation_file_id" => file.id,
                 "position" => 1,
                 "style" => "scale",
                 "multiple" => true,
                 "poll_opts" => [%{"content" => "1"}, %{"content" => "5"}]
               })

      assert %{multiple: ["a scale takes one answer"]} = errors_on(changeset)
    end

    test "a style that is neither is refused" do
      file = presentation_file_fixture()

      assert {:error, changeset} =
               Polls.create_poll(%{
                 "title" => "what is this",
                 "presentation_file_id" => file.id,
                 "position" => 1,
                 "style" => "pie chart",
                 "poll_opts" => [%{"content" => "a"}, %{"content" => "b"}]
               })

      assert errors_on(changeset)[:style]
    end
  end
end
