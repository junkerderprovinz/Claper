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

  describe "slider polls" do
    import Claper.{PollsFixtures, PresentationsFixtures}

    test "create_poll/1 accepts a slider poll without any pre-defined choice" do
      presentation_file = presentation_file_fixture()

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          type: :slider,
          min_value: 1,
          max_value: 10,
          poll_opts: []
        })

      assert poll.type == :slider
      assert poll.min_value == 1
      assert poll.max_value == 10
      assert poll.poll_opts == []
    end

    test "create_poll/1 rejects a range whose highest value is not above the lowest one" do
      presentation_file = presentation_file_fixture()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Polls.create_poll(%{
                 title: "some title",
                 position: 0,
                 presentation_file_id: presentation_file.id,
                 type: :slider,
                 min_value: 5,
                 max_value: 5,
                 poll_opts: []
               })

      assert "must be greater than the lowest value" in errors_on(changeset).max_value
    end

    test "submit_rating/4 records a rating nobody picked yet as a new poll_opt" do
      presentation_file = presentation_file_fixture(%{}, [:event])

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          type: :slider,
          min_value: 1,
          max_value: 10,
          poll_opts: []
        })

      assert {:ok, %Polls.Poll{} = updated_poll} =
               Polls.submit_rating(
                 "attendee-1",
                 presentation_file.event_id,
                 poll.id,
                 "7"
               )

      assert [%{content: "7", vote_count: 1}] = updated_poll.poll_opts
    end

    test "submit_rating/4 increments a rating already picked instead of duplicating it" do
      presentation_file = presentation_file_fixture(%{}, [:event])

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          type: :slider,
          min_value: 1,
          max_value: 10,
          poll_opts: []
        })

      {:ok, _} = Polls.submit_rating("attendee-1", presentation_file.event_id, poll.id, "7")

      {:ok, updated_poll} =
        Polls.submit_rating("attendee-2", presentation_file.event_id, poll.id, "7")

      assert [%{content: "7", vote_count: 2}] = updated_poll.poll_opts
    end

    test "submit_rating/4 records a poll_vote, so the attendee cannot rate twice" do
      presentation_file = presentation_file_fixture(%{}, [:event])

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          type: :slider,
          min_value: 1,
          max_value: 10,
          poll_opts: []
        })

      {:ok, _} = Polls.submit_rating("attendee-1", presentation_file.event_id, poll.id, "7")

      assert [%Polls.PollVote{}] = Polls.get_poll_vote("attendee-1", poll.id)
    end

    test "submit_rating/4 with a value outside the poll's range returns an error" do
      presentation_file = presentation_file_fixture(%{}, [:event])

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          type: :slider,
          min_value: 1,
          max_value: 10,
          poll_opts: []
        })

      assert {:error, :out_of_range} =
               Polls.submit_rating("attendee-1", presentation_file.event_id, poll.id, "42")

      assert {:error, :out_of_range} =
               Polls.submit_rating("attendee-1", presentation_file.event_id, poll.id, "0")

      assert {:error, :out_of_range} =
               Polls.submit_rating("attendee-1", presentation_file.event_id, poll.id, "seven")
    end

    test "average_rating/1 weights every value by the number of votes it got" do
      presentation_file = presentation_file_fixture()

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          type: :slider,
          min_value: 1,
          max_value: 10,
          poll_opts: [
            %{content: "2", vote_count: 1},
            %{content: "9", vote_count: 3}
          ]
        })

      assert Polls.average_rating(poll) == 7.3
    end

    test "average_rating/1 returns nil while nobody has rated yet" do
      presentation_file = presentation_file_fixture()

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          type: :slider,
          min_value: 1,
          max_value: 10,
          poll_opts: []
        })

      assert Polls.average_rating(poll) == nil
    end

    test "rating_distribution/1 covers the whole range and scales to the most picked value" do
      presentation_file = presentation_file_fixture()

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          type: :slider,
          min_value: 1,
          max_value: 3,
          poll_opts: [
            %{content: "1", vote_count: 1},
            %{content: "3", vote_count: 4}
          ]
        })

      assert [
               %{value: 1, vote_count: 1, percentage: 25},
               %{value: 2, vote_count: 0, percentage: 0},
               %{value: 3, vote_count: 4, percentage: 100}
             ] = Polls.rating_distribution(poll)
    end

    test "default_rating/1 starts the slider in the middle of the range" do
      presentation_file = presentation_file_fixture()

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          type: :slider,
          min_value: 1,
          max_value: 5,
          poll_opts: []
        })

      assert Polls.default_rating(poll) == 3
    end
  end
end
