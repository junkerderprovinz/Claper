defmodule ClaperWeb.AddinControllerTest do
  use ClaperWeb.ConnCase

  import Claper.{AccountsFixtures, PresentationsFixtures}

  setup %{conn: conn} do
    previous = Application.get_env(:claper, :presenter_embed_frame_ancestors)
    Application.put_env(:claper, :presenter_embed_frame_ancestors, "https://slides.example.com")

    on_exit(fn ->
      if previous do
        Application.put_env(:claper, :presenter_embed_frame_ancestors, previous)
      else
        Application.delete_env(:claper, :presenter_embed_frame_ancestors)
      end
    end)

    user = user_fixture()
    presentation_file = presentation_file_fixture(%{user: user}, [:event])
    presentation_state_fixture(%{presentation_file: presentation_file})
    event = Claper.Events.get_event_with_code(presentation_file.event.code)

    {:ok, token} = Claper.Events.create_addin_token(event, user)

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      user: user,
      event: event,
      token: token,
      presentation_file: presentation_file
    }
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  describe "authorisation" do
    test "no token is refused", %{conn: conn} do
      assert json_response(get(conn, ~p"/api/addin/polls"), 401)
    end

    test "a nonsense token is refused", %{conn: conn} do
      assert conn |> auth("not-a-token") |> get(~p"/api/addin/polls") |> json_response(401)
    end

    # The whole point of a second context: the link that travels inside a shared
    # document must not be able to write.
    test "the read-only embed token does not open the api", %{
      conn: conn,
      user: user,
      event: event
    } do
      {:ok, embed} = Claper.Events.create_presenter_embed_token(event, user)

      assert conn |> auth(embed) |> get(~p"/api/addin/polls") |> json_response(401)
    end

    test "a user who does not lead the event gets no token", %{event: event} do
      stranger = user_fixture()

      assert {:error, :unauthorized} = Claper.Events.create_addin_token(event, stranger)
    end

    test "revoking closes the api", %{conn: conn, user: user, event: event, token: token} do
      assert {:ok, 1} = Claper.Events.revoke_addin_tokens(event, user)

      assert conn |> auth(token) |> get(~p"/api/addin/polls") |> json_response(401)
    end

    test "the api is gone when the feature is switched off", %{conn: conn, token: token} do
      Application.delete_env(:claper, :presenter_embed_frame_ancestors)

      assert conn |> auth(token) |> get(~p"/api/addin/polls") |> json_response(404)
    end
  end

  describe "listing" do
    test "returns the event and its polls", %{
      conn: conn,
      token: token,
      event: event,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        title: "existing poll"
      })

      body = conn |> auth(token) |> get(~p"/api/addin/polls") |> json_response(200)

      assert body["event"]["code"] == event.code
      assert [%{"title" => "existing poll", "options" => [_ | _]}] = body["polls"]
    end
  end

  describe "creating" do
    test "creates a poll and returns its id", %{conn: conn, token: token} do
      body =
        conn
        |> auth(token)
        |> post(~p"/api/addin/polls", %{title: "How was it?", options: ["Good", "Bad"]})
        |> json_response(201)

      assert body["title"] == "How was it?"
      assert length(body["options"]) == 2
      assert is_integer(body["id"])
    end

    test "the created poll is reachable through the pinned embed", %{
      conn: conn,
      user: user,
      event: event,
      token: token
    } do
      created =
        conn
        |> auth(token)
        |> post(~p"/api/addin/polls", %{title: "pinned poll", options: ["A", "B"]})
        |> json_response(201)

      {:ok, embed} = Claper.Events.create_presenter_embed_token(event, user)

      html =
        build_conn()
        |> get(~p"/embed/interaction/#{embed}?poll=#{created["id"]}")
        |> html_response(200)

      assert html =~ "pinned poll"
      assert user
    end

    test "a title alone is refused", %{conn: conn, token: token} do
      assert conn
             |> auth(token)
             |> post(~p"/api/addin/polls", %{title: "no options"})
             |> json_response(422)
    end

    test "one option is not a poll", %{conn: conn, token: token} do
      assert conn
             |> auth(token)
             |> post(~p"/api/addin/polls", %{title: "t", options: ["only one"]})
             |> json_response(422)
    end

    test "the listing says how long the Claper deck is", %{conn: conn, token: token} do
      body = conn |> auth(token) |> get(~p"/api/addin/polls") |> json_response(200)

      assert body["event"]["deck_length"] == 42
    end
  end

  describe "editing" do
    setup %{conn: conn, token: token} do
      poll =
        conn
        |> auth(token)
        |> post(~p"/api/addin/polls", %{title: "before", options: ["A", "B"]})
        |> json_response(201)

      %{poll: poll}
    end

    test "renames without touching the answers", %{conn: conn, token: token, poll: poll} do
      body =
        conn
        |> auth(token)
        |> patch(~p"/api/addin/polls/#{poll["id"]}", %{title: "after"})
        |> json_response(200)

      assert body["title"] == "after"
      assert Enum.map(body["options"], & &1["content"]) == ["A", "B"]
    end

    test "replaces the answers when they are sent", %{conn: conn, token: token, poll: poll} do
      body =
        conn
        |> auth(token)
        |> patch(~p"/api/addin/polls/#{poll["id"]}", %{title: "after", options: ["X", "Y", "Z"]})
        |> json_response(200)

      assert Enum.map(body["options"], & &1["content"]) == ["X", "Y", "Z"]
    end

    test "deletes", %{conn: conn, token: token, poll: poll} do
      assert conn |> auth(token) |> delete(~p"/api/addin/polls/#{poll["id"]}") |> response(204)

      remaining =
        conn |> auth(token) |> get(~p"/api/addin/polls") |> json_response(200) |> Map.get("polls")

      refute Enum.any?(remaining, &(&1["id"] == poll["id"]))
    end

    # The token is the whole authorisation, so an id from another event must be
    # invisible rather than merely refused.
    test "a poll of another event is not found", %{conn: conn, token: token} do
      other_user = user_fixture()
      other_file = presentation_file_fixture(%{user: other_user}, [:event])

      foreign =
        Claper.PollsFixtures.poll_fixture(%{
          presentation_file_id: other_file.id,
          title: "someone else's"
        })

      assert conn
             |> auth(token)
             |> patch(~p"/api/addin/polls/#{foreign.id}", %{title: "hijacked"})
             |> json_response(404)

      assert conn
             |> auth(token)
             |> delete(~p"/api/addin/polls/#{foreign.id}")
             |> json_response(404)

      assert Claper.Polls.get_poll!(foreign.id).title == "someone else's"
    end

    test "a nonsense id is not found", %{conn: conn, token: token} do
      assert conn
             |> auth(token)
             |> delete(~p"/api/addin/polls/not-a-number")
             |> json_response(404)
    end
  end

  describe "creating extra" do
    test "an empty title is refused", %{conn: conn, token: token} do
      assert conn
             |> auth(token)
             |> post(~p"/api/addin/polls", %{title: "   ", options: ["A", "B"]})
             |> json_response(422)
    end
  end
end
