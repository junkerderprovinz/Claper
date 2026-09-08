defmodule Claper.SelfPacedTest do
  @moduledoc """
  The list a room works through when it answers at its own pace instead of
  following the presenter.
  """

  use Claper.DataCase

  alias Claper.Interactions

  import Claper.PollsFixtures
  import Claper.FormsFixtures
  import Claper.QuizzesFixtures
  import Claper.PresentationsFixtures
  import Claper.EmbedsFixtures

  setup do
    deck = presentation_file_fixture()
    event = Claper.Events.get_event!(deck.event_id) |> Claper.Repo.preload(:presentation_file)
    %{deck: deck, event: event}
  end

  test "only what the presenter has released", %{deck: deck, event: event} do
    poll_fixture(%{presentation_file_id: deck.id, position: 1, enabled: true, title: "open one"})

    poll_fixture(%{
      presentation_file_id: deck.id,
      position: 2,
      enabled: false,
      title: "still closed"
    })

    titles = event |> Interactions.list_enabled_interactions() |> Enum.map(& &1.title)

    assert "open one" in titles
    refute "still closed" in titles
  end

  # A questionnaire is read in the order it was written, and the order it was
  # written in is the order of the slides.
  test "in slide order, not in the order the tables were read", %{deck: deck, event: event} do
    quiz_fixture(%{presentation_file_id: deck.id, position: 3, enabled: true, title: "third"})
    poll_fixture(%{presentation_file_id: deck.id, position: 1, enabled: true, title: "first"})
    form_fixture(%{presentation_file_id: deck.id, position: 2, enabled: true, title: "second"})

    assert ["first", "second", "third"] =
             event |> Interactions.list_enabled_interactions() |> Enum.map(& &1.title)
  end

  # An embed is a page put on a slide to look at, not a question with an
  # answer, so a list of things still to answer is the wrong place for it.
  test "an embed is not a question", %{deck: deck, event: event} do
    embed_fixture(%{presentation_file_id: deck.id, position: 1, enabled: true})

    assert Interactions.list_enabled_interactions(event) == []
  end

  test "an event with nothing released has an empty list", %{event: event} do
    assert Interactions.list_enabled_interactions(event) == []
  end

  test "the switch is off unless somebody turns it on", %{event: event} do
    refute event.self_paced

    assert {:ok, updated} = Claper.Events.update_event(event, %{"self_paced" => true})
    assert updated.self_paced
  end
end
