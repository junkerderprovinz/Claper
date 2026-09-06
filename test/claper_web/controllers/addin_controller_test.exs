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

  describe "quizzes" do
    defp a_quiz(overrides \\ %{}) do
      Map.merge(
        %{
          title: "Round one",
          questions: [
            %{
              content: "Capital of France?",
              options: [
                %{content: "Paris", correct: true},
                %{content: "Lyon", correct: false}
              ]
            }
          ]
        },
        overrides
      )
    end

    test "creates a quiz with its questions and answers", %{conn: conn, token: token} do
      body = conn |> auth(token) |> post(~p"/api/addin/quizzes", a_quiz()) |> json_response(201)

      assert body["title"] == "Round one"
      assert [%{"content" => "Capital of France?", "options" => options}] = body["questions"]
      assert [%{"content" => "Paris", "correct" => true}, %{"correct" => false}] = options
    end

    # A quiz has a right answer, and a poll does not. Releasing the results of a
    # quiz the moment it is created would put the answer on the slide while the
    # room is still answering.
    test "a new quiz keeps its results back", %{conn: conn, token: token} do
      body = conn |> auth(token) |> post(~p"/api/addin/quizzes", a_quiz()) |> json_response(201)

      assert body["show_results"] == false
    end

    test "lists the quizzes of this event", %{conn: conn, token: token} do
      conn |> auth(token) |> post(~p"/api/addin/quizzes", a_quiz()) |> json_response(201)

      body = conn |> auth(token) |> get(~p"/api/addin/quizzes") |> json_response(200)

      assert [%{"title" => "Round one"}] = body["quizzes"]
    end

    test "renames a quiz and replaces its questions", %{conn: conn, token: token} do
      created =
        conn |> auth(token) |> post(~p"/api/addin/quizzes", a_quiz()) |> json_response(201)

      body =
        conn
        |> auth(token)
        |> patch(~p"/api/addin/quizzes/#{created["id"]}", %{
          title: "Round two",
          questions: [
            %{
              content: "Capital of Italy?",
              options: [%{content: "Rome", correct: true}, %{content: "Milan", correct: false}]
            }
          ]
        })
        |> json_response(200)

      assert body["title"] == "Round two"
      assert [%{"content" => "Capital of Italy?"}] = body["questions"]
    end

    test "deletes a quiz", %{conn: conn, token: token} do
      created =
        conn |> auth(token) |> post(~p"/api/addin/quizzes", a_quiz()) |> json_response(201)

      assert conn
             |> auth(token)
             |> delete(~p"/api/addin/quizzes/#{created["id"]}")
             |> response(204)

      assert conn
             |> auth(token)
             |> get(~p"/api/addin/quizzes")
             |> json_response(200)
             |> Map.get("quizzes") == []
    end

    test "a question with no right answer is refused", %{conn: conn, token: token} do
      payload =
        a_quiz(%{
          questions: [
            %{
              content: "Capital of France?",
              options: [%{content: "Paris", correct: false}, %{content: "Lyon", correct: false}]
            }
          ]
        })

      assert conn |> auth(token) |> post(~p"/api/addin/quizzes", payload) |> json_response(422)
    end

    test "a question with one answer is refused", %{conn: conn, token: token} do
      payload =
        a_quiz(%{
          questions: [
            %{content: "Capital of France?", options: [%{content: "Paris", correct: true}]}
          ]
        })

      assert conn |> auth(token) |> post(~p"/api/addin/quizzes", payload) |> json_response(422)
    end

    test "a quiz with no questions is refused", %{conn: conn, token: token} do
      assert conn
             |> auth(token)
             |> post(~p"/api/addin/quizzes", a_quiz(%{questions: []}))
             |> json_response(422)
    end

    test "a quiz of another event is not found", %{conn: conn, token: token} do
      other_user = user_fixture()
      other_file = presentation_file_fixture(%{user: other_user}, [:event])

      foreign =
        Claper.QuizzesFixtures.quiz_fixture(%{presentation_file_id: other_file.id})

      assert conn
             |> auth(token)
             |> patch(~p"/api/addin/quizzes/#{foreign.id}", %{title: "hijacked"})
             |> json_response(404)

      assert conn
             |> auth(token)
             |> delete(~p"/api/addin/quizzes/#{foreign.id}")
             |> json_response(404)
    end
  end

  describe "the slide link" do
    test "issues a read-only link the sidebar's own key cannot be swapped for", %{
      conn: conn,
      token: token
    } do
      body = conn |> auth(token) |> post(~p"/api/addin/embed_token") |> json_response(201)

      assert is_binary(body["token"])
      assert body["token"] != token

      # It reads the presenter view.
      assert build_conn() |> get(~p"/embed/interaction/#{body["token"]}") |> html_response(200)

      # And it does not open the writing api.
      assert build_conn()
             |> put_req_header("accept", "application/json")
             |> put_req_header("authorization", "Bearer #{body["token"]}")
             |> get(~p"/api/addin/polls")
             |> json_response(401)
    end

    # One event can be used by several presentations, and a deck can hold many
    # blocks. A link made for a second deck must not blank the first one: that
    # happened in testing within minutes of the rotating version existing.
    test "asking again leaves the previous link working", %{conn: conn, token: token} do
      first = conn |> auth(token) |> post(~p"/api/addin/embed_token") |> json_response(201)
      second = conn |> auth(token) |> post(~p"/api/addin/embed_token") |> json_response(201)

      refute first["token"] == second["token"]
      assert build_conn() |> get(~p"/embed/interaction/#{first["token"]}") |> html_response(200)
      assert build_conn() |> get(~p"/embed/interaction/#{second["token"]}") |> html_response(200)
    end

    # The off switch has to stay one action, or it is not an off switch.
    test "revoking closes every link the sidebar made", %{
      conn: conn,
      user: user,
      event: event,
      token: token
    } do
      first = conn |> auth(token) |> post(~p"/api/addin/embed_token") |> json_response(201)
      second = conn |> auth(token) |> post(~p"/api/addin/embed_token") |> json_response(201)

      {:ok, _count} = Claper.Events.revoke_presenter_embed_tokens(event, user)

      assert build_conn() |> get(~p"/embed/interaction/#{first["token"]}") |> html_response(404)
      assert build_conn() |> get(~p"/embed/interaction/#{second["token"]}") |> html_response(404)
    end

    # Same for the event simply ending, which is the case nobody presses a
    # button for.
    test "ending the event closes every link the sidebar made", %{
      conn: conn,
      event: event,
      token: token
    } do
      made = conn |> auth(token) |> post(~p"/api/addin/embed_token") |> json_response(201)

      {:ok, _event} = Claper.Events.terminate_event(event)

      assert build_conn() |> get(~p"/embed/interaction/#{made["token"]}") |> html_response(404)
    end
  end

  describe "the catalogue a slide reads" do
    setup %{event: event, user: user} do
      {:ok, embed} = Claper.Events.create_presenter_embed_token(event, user)
      %{embed: embed}
    end

    test "lists what a block could show", %{
      conn: conn,
      token: token,
      embed: embed,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        title: "a poll"
      })

      conn
      |> auth(token)
      |> post(~p"/api/addin/quizzes", %{
        title: "a quiz",
        questions: [
          %{
            content: "Q",
            options: [%{content: "A", correct: true}, %{content: "B", correct: false}]
          }
        ]
      })
      |> json_response(201)

      body = build_conn() |> get(~p"/api/embed/#{embed}/interactions") |> json_response(200)

      assert [%{"title" => "a poll"}] = body["polls"]
      assert [%{"title" => "a quiz"}] = body["quizzes"]
    end

    # The catalogue exists so a slide can name what it shows. It must not become
    # a way to read the answers before the presenter releases them.
    test "carries no options, no counts and no correct answers", %{
      conn: conn,
      token: token,
      embed: embed,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        title: "a poll"
      })

      conn
      |> auth(token)
      |> post(~p"/api/addin/quizzes", %{
        title: "a quiz",
        questions: [
          %{
            content: "Capital of France?",
            options: [%{content: "Paris", correct: true}, %{content: "Lyon", correct: false}]
          }
        ]
      })
      |> json_response(201)

      raw = build_conn() |> get(~p"/api/embed/#{embed}/interactions") |> response(200)

      refute raw =~ "Paris"
      refute raw =~ "correct"
      refute raw =~ "Capital of France?"
    end

    test "an unknown link is not found", %{conn: _conn} do
      assert build_conn() |> get(~p"/api/embed/not-a-token/interactions") |> json_response(404)
    end

    test "a revoked link closes the catalogue", %{event: event, user: user, embed: embed} do
      {:ok, _} = Claper.Events.revoke_presenter_embed_tokens(event, user)

      assert build_conn() |> get(~p"/api/embed/#{embed}/interactions") |> json_response(404)
    end

    test "the writing key is not a catalogue key", %{token: token} do
      assert build_conn() |> get(~p"/api/embed/#{token}/interactions") |> json_response(404)
    end
  end
end
