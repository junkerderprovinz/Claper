defmodule Claper.PollShapesTest do
  @moduledoc """
  The four shapes added after bars, the scale and the ranking.

  All of them share one table and differ only in what an answer is, so what is
  worth pinning down is exactly that difference: how the rows are read back into
  a result, and which combinations the changeset refuses instead of letting a
  room see something nobody chose.
  """

  use Claper.DataCase

  alias Claper.Polls
  alias Claper.Polls.Poll

  import Claper.PollsFixtures
  import Claper.PresentationsFixtures

  defp poll_with(style, attrs \\ %{}) do
    presentation_file = presentation_file_fixture()

    base = %{
      style: style,
      presentation_file_id: presentation_file.id,
      title: "some question"
    }

    poll_fixture(Map.merge(base, attrs))
  end

  describe "which shapes a poll may take" do
    test "the four new ones are accepted" do
      for style <- ~w(points wheel) do
        assert %Poll{style: ^style} = poll_with(style)
      end
    end

    test "a picture question is refused without a picture" do
      presentation_file = presentation_file_fixture()

      attrs = %{
        title: "where does it hurt",
        style: "pins",
        position: 0,
        presentation_file_id: presentation_file.id,
        poll_opts: [%{content: "pin", vote_count: 0}]
      }

      assert {:error, changeset} = Polls.create_poll(attrs)
      assert %{image: ["a pins poll needs a picture to pin on"]} = errors_on(changeset)

      assert {:ok, _poll} =
               Polls.create_poll(Map.put(attrs, :image, "/uploads/addin/abc.png"))
    end

    test "a shape nobody has heard of is refused rather than stored" do
      presentation_file = presentation_file_fixture()

      assert {:error, changeset} =
               Polls.create_poll(%{
                 title: "t",
                 style: "spiral",
                 position: 0,
                 presentation_file_id: presentation_file.id,
                 poll_opts: [%{content: "a", vote_count: 0}, %{content: "b", vote_count: 0}]
               })

      assert %{style: _} = errors_on(changeset)
    end

    # "Several answers" says nothing on a shape that already uses all of them,
    # and the contradiction is refused where it was made rather than ignored.
    test "several answers is refused on the shapes it means nothing for" do
      for style <- ~w(points pins wheel) do
        presentation_file = presentation_file_fixture()

        attrs = %{
          title: "t",
          style: style,
          multiple: true,
          position: 0,
          presentation_file_id: presentation_file.id,
          image: "/uploads/addin/abc.png",
          poll_opts: [%{content: "a", vote_count: 0}, %{content: "b", vote_count: 0}]
        }

        assert {:error, changeset} = Polls.create_poll(attrs)
        assert %{multiple: _} = errors_on(changeset), "#{style} accepted multiple"
      end
    end

    test "a budget outside one to a thousand is refused" do
      presentation_file = presentation_file_fixture()

      attrs = %{
        title: "t",
        style: "points",
        position: 0,
        presentation_file_id: presentation_file.id,
        poll_opts: [%{content: "a", vote_count: 0}, %{content: "b", vote_count: 0}]
      }

      assert {:error, _} = Polls.create_poll(Map.put(attrs, :points_budget, 0))
      assert {:error, _} = Polls.create_poll(Map.put(attrs, :points_budget, 5000))
      assert {:ok, _} = Polls.create_poll(Map.put(attrs, :points_budget, 10))
    end
  end

  describe "Poll.spent/2" do
    test "nothing spent is every option at zero, not an empty list" do
      poll = poll_with("points")
      result = Poll.spent(poll, [])

      assert length(result) == 2
      assert Enum.all?(result, fn {_opt, points, share} -> points == 0 and share == 0.0 end)
    end

    test "the most expensive option comes first, with its share of the total" do
      poll = poll_with("points")
      [a, b] = poll.poll_opts

      votes = [
        %{poll_opt_id: a.id, points: 30},
        %{poll_opt_id: b.id, points: 70},
        %{poll_opt_id: a.id, points: 20}
      ]

      assert [{first, 70, 58.3}, {second, 50, 41.7}] = Poll.spent(poll, votes)
      assert first.id == b.id
      assert second.id == a.id
    end

    # Rows of other shapes live in the same table, and a ranking's place would
    # otherwise be counted as points.
    test "rows without points are not counted" do
      poll = poll_with("points")
      [a, _b] = poll.poll_opts

      votes = [%{poll_opt_id: a.id, points: nil, rank: 1}]

      assert Enum.all?(Poll.spent(poll, votes), fn {_opt, points, _} -> points == 0 end)
    end

    test "a tie keeps the same order every time, so the slide does not reshuffle" do
      poll = poll_with("points")
      [a, b] = poll.poll_opts
      votes = [%{poll_opt_id: a.id, points: 10}, %{poll_opt_id: b.id, points: 10}]

      assert Poll.spent(poll, votes) == Poll.spent(poll, votes)
      assert [{first, _, _}, _] = Poll.spent(poll, votes)
      assert first.id == min(a.id, b.id)
    end
  end

  describe "Poll.pins/1" do
    test "only the rows that carry a spot" do
      votes = [
        %{x: 0.25, y: 0.5},
        %{x: nil, y: nil},
        %{x: 0.75, y: 0.1}
      ]

      assert Poll.pins(votes) == [{0.25, 0.5}, {0.75, 0.1}]
    end

    test "nothing tapped is nothing to draw" do
      assert Poll.pins([]) == []
    end
  end

  describe "Poll.answerable?/1" do
    test "a wheel is spun, not answered" do
      refute Poll.answerable?(%Poll{style: "wheel"})
    end

    test "every other shape is answered" do
      for style <- ~w(bars scale ranking points pins) do
        assert Poll.answerable?(%Poll{style: style}), "#{style} was not answerable"
      end
    end
  end

  describe "spending a budget" do
    test "one row per option that got something, and none for the rest" do
      poll = poll_with("points")
      [a, b] = poll.poll_opts

      assert {:ok, _} =
               Polls.allocate("someone", Ecto.UUID.generate(), %{a.id => 60, b.id => 0}, poll.id)

      rows = Polls.list_poll_votes(poll.id)
      assert [%{poll_opt_id: opt_id, points: 60}] = rows
      assert opt_id == a.id
    end

    # The bar beside a poll counts people. Points are not people, and folding
    # them into the same number would make that label a lie.
    test "the counter on the option is left alone" do
      poll = poll_with("points")
      [a, _b] = poll.poll_opts

      assert {:ok, _} = Polls.allocate("someone", Ecto.UUID.generate(), %{a.id => 40}, poll.id)

      reloaded = Polls.get_poll!(poll.id)
      assert Enum.all?(reloaded.poll_opts, &(&1.vote_count in [0, nil]))
    end
  end

  describe "tapping a picture" do
    test "the spot is stored against the question's own option" do
      poll = poll_with("pins", %{image: "/uploads/addin/abc.png"})

      assert {:ok, _} = Polls.pin("someone", Ecto.UUID.generate(), {0.4, 0.6}, poll.id)

      assert [%{x: x, y: y, poll_opt_id: opt_id}] = Polls.list_poll_votes(poll.id)
      assert_in_delta x, 0.4, 0.0001
      assert_in_delta y, 0.6, 0.0001
      assert opt_id == hd(poll.poll_opts).id
    end

    # The numbers arrive from a browser and are the one thing here a person can
    # hand-edit.
    test "a spot outside the picture is refused" do
      poll = poll_with("pins", %{image: "/uploads/addin/abc.png"})

      assert {:error, _} = Polls.pin("someone", Ecto.UUID.generate(), {1.5, 0.5}, poll.id)
      assert {:error, _} = Polls.pin("someone", Ecto.UUID.generate(), {0.5, -0.2}, poll.id)
      assert Polls.list_poll_votes(poll.id) == []
    end
  end
end
