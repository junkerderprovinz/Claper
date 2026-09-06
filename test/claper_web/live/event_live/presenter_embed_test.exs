defmodule ClaperWeb.EventLive.PresenterEmbedTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{AccountsFixtures, PresentationsFixtures}

  setup do
    # The feature is off until an operator names the origins that may frame it,
    # so every test here has to switch it on the way a server would.
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
    state = presentation_state_fixture(%{presentation_file: presentation_file})
    event = Claper.Events.get_event_with_code(presentation_file.event.code)

    {:ok, token} = Claper.Events.create_presenter_embed_token(event, user)

    %{
      user: user,
      event: event,
      token: token,
      presentation_file: presentation_file,
      state: state
    }
  end

  describe "off switch" do
    test "without an allow list a valid token is answered with 404", %{conn: conn, token: token} do
      Application.delete_env(:claper, :presenter_embed_frame_ancestors)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert conn.status == 404
    end

    test "a value the sanitiser rejects leaves the feature off", %{conn: conn, token: token} do
      Application.put_env(
        :claper,
        :presenter_embed_frame_ancestors,
        "https://a.com; default-src *"
      )

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert conn.status == 404
    end
  end

  # Slide files are numbered from 1 while `position` counts from 0, so position
  # 0 is `1.jpg`. The fixture deck has 42 pages.
  describe "slides" do
    test "only the projected page is in the markup", %{conn: conn, token: token} do
      {:ok, _view, html} = live(conn, ~p"/embed/presenter/#{token}")

      assert html =~ "/uploads/123456/1.jpg"

      for page <- [2, 8, 42] do
        refute html =~ "/uploads/123456/#{page}.jpg"
      end
    end

    test "moving the presentation moves the page the embed shows", %{
      conn: conn,
      token: token,
      state: state
    } do
      {:ok, view, _html} = live(conn, ~p"/embed/presenter/#{token}")

      # This broadcasts :state_updated, which is what an open frame listens for.
      {:ok, _state} = Claper.Presentations.update_presentation_state(state, %{"position" => 3})

      html = render(view)
      assert html =~ "/uploads/123456/4.jpg"
      refute html =~ "/uploads/123456/1.jpg"
    end

    test "the owner's own presenter view still carries the whole deck", %{
      conn: conn,
      user: user,
      event: event
    } do
      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/e/#{event.code}/presenter")

      assert html =~ "/uploads/123456/1.jpg"
      assert html =~ "/uploads/123456/42.jpg"
    end
  end

  describe "token authorization" do
    test "a valid token renders the presenter view without a logged in user", %{
      conn: conn,
      token: token
    } do
      {:ok, _view, html} = live(conn, ~p"/embed/presenter/#{token}")

      assert html =~ ~s(id="presenter")
    end

    test "an unknown token is answered with 404", %{conn: conn} do
      unknown = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      conn = get(conn, ~p"/embed/presenter/#{unknown}")

      assert response(conn, 404)
    end

    test "a malformed token is answered with 404", %{conn: conn} do
      conn = get(conn, ~p"/embed/presenter/not-a-token")

      assert response(conn, 404)
    end

    test "a revoked token is answered with 404", %{
      conn: conn,
      user: user,
      event: event,
      token: token
    } do
      assert {:ok, 1} = Claper.Events.revoke_presenter_embed_tokens(event, user)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert response(conn, 404)
    end

    test "creating a link again invalidates the previous one", %{
      conn: conn,
      user: user,
      event: event,
      token: token
    } do
      {:ok, new_token} = Claper.Events.create_presenter_embed_token(event, user)

      assert response(get(conn, ~p"/embed/presenter/#{token}"), 404)
      assert {:ok, _view, _html} = live(conn, ~p"/embed/presenter/#{new_token}")
    end

    test "a token of an expired event is answered with 404", %{
      conn: conn,
      event: event,
      token: token
    } do
      {:ok, _event} =
        event
        |> Ecto.Changeset.change(
          expired_at:
            NaiveDateTime.utc_now()
            |> NaiveDateTime.truncate(:second)
            |> NaiveDateTime.add(-60, :second)
        )
        |> Claper.Repo.update()

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert response(conn, 404)
    end
  end

  describe "read-only guarantee" do
    # The embeddable view is safe because the presenter LiveView and the two
    # components it renders define no handle_event/3 at all, so a manipulated
    # client has no server side write path. A later change that adds one would
    # silently turn this route into a writable surface, hence the guard.
    test "the presenter view exposes no client triggered events" do
      for module <- [
            ClaperWeb.EventLive.Presenter,
            ClaperWeb.EventLive.ManageableQuizComponent,
            ClaperWeb.EventLive.EmbedIframeComponent
          ] do
        Code.ensure_loaded!(module)

        refute function_exported?(module, :handle_event, 3),
               "#{inspect(module)} defines handle_event/3, which the embeddable presenter route " <>
                 "would expose without authentication"
      end
    end

    # The absence of handle_event/3 is not the whole story. The join screen
    # carries the event code, and the event code is a write path of its own:
    # /e/:code needs no account, so a viewer who reads the code out of the
    # markup can post and vote. Hiding the screen with opacity is not enough,
    # it has to stay out of the response.
    test "the embed response does not carry the event code", %{
      conn: conn,
      event: event,
      token: token
    } do
      conn = get(conn, ~p"/embed/presenter/#{token}")
      html = html_response(conn, 200)

      refute html =~ event.code
      refute html =~ String.upcase(event.code)
      refute html =~ "joinScreen"
    end

    test "the regular presenter route still shows the join screen", %{
      conn: conn,
      user: user,
      event: event
    } do
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/e/#{event.code}/presenter")

      assert html_response(conn, 200) =~ "joinScreen"
    end

    # poll_visible is false by default, and the projected view only fades the
    # block out. On the beamer the sole reader is the logged in owner. Behind an
    # embed link the markup is public to whoever holds the link.
    test "a hidden poll is absent from the embed and present on the presenter route", %{
      conn: conn,
      user: user,
      event: event,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        title: "secret poll title"
      })

      embed = get(conn, ~p"/embed/presenter/#{token}") |> html_response(200)

      refute embed =~ "secret poll title"
      refute embed =~ "some option 1"

      projected =
        conn
        |> log_in_user(user)
        |> get(~p"/e/#{event.code}/presenter")
        |> html_response(200)

      assert projected =~ "secret poll title"
    end

    test "a visible poll is still shown in the embed", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        title: "announced poll title"
      })

      {:ok, _state} =
        Claper.Presentations.update_presentation_state(
          Claper.Repo.get_by!(Claper.Presentations.PresentationState,
            presentation_file_id: presentation_file.id
          ),
          %{poll_visible: true}
        )

      assert get(conn, ~p"/embed/presenter/#{token}") |> html_response(200) =~
               "announced poll title"
    end

    # The quiz overlay carries the correct answer marked with bg-green-600.
    # show_results false only fades it, so an embed would ship the answer key
    # while the quiz runs.
    test "a quiz with hidden results is absent from the embed", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.QuizzesFixtures.quiz_fixture(%{
        presentation_file: presentation_file,
        position: 0,
        enabled: true,
        show_results: false,
        title: "secret quiz title"
      })

      embed = get(conn, ~p"/embed/presenter/#{token}") |> html_response(200)

      refute embed =~ "secret quiz title"
      refute embed =~ "some question content"
      refute embed =~ "option 1"
    end

    # Without this the test above cannot fail for the right reason: a quiz that
    # never renders at all would satisfy every refute in it.
    test "a quiz whose results the owner released is present in the embed", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.QuizzesFixtures.quiz_fixture(%{
        presentation_file: presentation_file,
        position: 0,
        enabled: true,
        show_results: true,
        title: "released quiz title"
      })

      embed = get(conn, ~p"/embed/presenter/#{token}") |> html_response(200)

      assert embed =~ "released quiz title"
    end

    # "Attendees can view the web content on their device" starts unticked. An
    # embed link is another device.
    test "web content the owner did not release is absent from the embed", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.EmbedsFixtures.embed_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        enabled: true,
        attendee_visibility: false,
        provider: "custom",
        content: ~s(<iframe src="https://internal.example.org/SECRET-BOARD"></iframe>)
      })

      refute get(conn, ~p"/embed/presenter/#{token}") |> html_response(200) =~
               "SECRET-BOARD"
    end

    test "web content the owner released is shown in the embed", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.EmbedsFixtures.embed_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        enabled: true,
        attendee_visibility: true,
        provider: "custom",
        content: ~s(<iframe src="https://public.example.org/SHARED-BOARD"></iframe>)
      })

      assert get(conn, ~p"/embed/presenter/#{token}") |> html_response(200) =~
               "SHARED-BOARD"
    end

    # show_results is the same kind of choice, and the attendee view hides both
    # the bar and the numbers when it is off.
    test "poll results the owner hid are absent from the embed", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      # Votes have to differ, or the bar renders the same string with the guard
      # on and off and only the number span is really under test.
      poll =
        Claper.PollsFixtures.poll_fixture(%{
          presentation_file_id: presentation_file.id,
          position: 0,
          title: "counted poll",
          show_results: false,
          poll_opts: [
            %{content: "leading option", vote_count: 3},
            %{content: "trailing option", vote_count: 1}
          ]
        })

      show_poll(presentation_file)

      html = get(conn, ~p"/embed/presenter/#{token}") |> html_response(200)

      assert html =~ "counted poll"
      assert html =~ "leading option"
      refute html =~ "75% (3)"
      refute html =~ "width: 75%"
      assert html =~ "width: 0%"

      assert poll.show_results == false
    end

    # The counterpart: with the same fixture and the guard released, both the
    # bar and the numbers do appear, so the refutes above cannot pass vacuously.
    test "poll results the owner released are present in the embed", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        title: "counted poll",
        show_results: true,
        poll_opts: [
          %{content: "leading option", vote_count: 3},
          %{content: "trailing option", vote_count: 1}
        ]
      })

      show_poll(presentation_file)

      html = get(conn, ~p"/embed/presenter/#{token}") |> html_response(200)

      assert html =~ "75% (3)"
      assert html =~ "width: 75%"
    end
  end

  describe "interaction only view" do
    test "carries the released poll but no slide at all", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        title: "counted poll",
        show_results: true,
        poll_opts: [
          %{content: "leading option", vote_count: 3},
          %{content: "trailing option", vote_count: 1}
        ]
      })

      show_poll(presentation_file)

      html = get(conn, ~p"/embed/interaction/#{token}") |> html_response(200)

      assert html =~ "counted poll"
      assert html =~ "75% (3)"
      refute html =~ "/uploads/123456/"
      refute html =~ ~s(id="slider-wrapper")
    end

    test "sits on a transparent ground rather than a black one", %{conn: conn, token: token} do
      interaction = get(conn, ~p"/embed/interaction/#{token}") |> html_response(200)
      presenter = get(conn, ~p"/embed/presenter/#{token}") |> html_response(200)

      assert interaction =~ "background: transparent"
      assert presenter =~ "background: black"
    end

    # The first live test in PowerPoint showed nothing at all: the ground had
    # been made transparent while the text stayed white, which is invisible on a
    # white slide. Nothing in the markup was wrong, so no test could catch it.
    test "brings its own light ground so the text is not white on white", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        title: "readable poll",
        show_results: true
      })

      show_poll(presentation_file)

      html = get(conn, ~p"/embed/interaction/#{token}") |> html_response(200)
      poll_block = html |> String.split(~s(id="poll")) |> Enum.at(1) |> String.slice(0, 1200)

      assert poll_block =~ "bg-white"
      assert poll_block =~ "text-gray-900"
      refute poll_block =~ "text-white"
    end

    test "the same token opens both views", %{conn: conn, token: token} do
      assert {:ok, _view, _html} = live(conn, ~p"/embed/interaction/#{token}")
      assert {:ok, _view, _html} = live(conn, ~p"/embed/presenter/#{token}")
    end

    test "a revoked token closes the interaction view too", %{
      conn: conn,
      user: user,
      event: event,
      token: token
    } do
      {:ok, 1} = Claper.Events.revoke_presenter_embed_tokens(event, user)

      assert response(get(conn, ~p"/embed/interaction/#{token}"), 404)
    end
  end

  describe "identity" do
    # The embed must be the same page for everyone holding the link. A visitor
    # who happens to be logged in must not get their own session on it, or the
    # view starts answering as a user the link never authorised.
    test "a logged in visitor is still nobody on the embed", %{
      conn: conn,
      user: user,
      token: token
    } do
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/embed/presenter/#{token}")

      assert :sys.get_state(view.pid).socket.assigns.current_user == nil
    end
  end

  describe "subtitles" do
    # "presenter" means the screen in the room. An embed link leaves the room.
    test "captions meant for the room alone stay out of the embed", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      {:ok, _config} =
        Claper.Transcriptions.create_transcription_config(%{
          presentation_file_id: presentation_file.id,
          enabled: true,
          visibility: "presenter"
        })

      {:ok, view, _html} = live(conn, ~p"/embed/presenter/#{token}")
      send(view.pid, {:transcription_delta, "spoken in the room"})

      refute render(view) =~ "spoken in the room"
    end

    test "captions meant for every device do reach the embed", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      {:ok, _config} =
        Claper.Transcriptions.create_transcription_config(%{
          presentation_file_id: presentation_file.id,
          enabled: true,
          visibility: "both"
        })

      {:ok, view, _html} = live(conn, ~p"/embed/presenter/#{token}")
      send(view.pid, {:transcription_delta, "meant for everyone"})

      assert render(view) =~ "meant for everyone"
    end
  end

  defp show_poll(presentation_file) do
    {:ok, state} =
      Claper.Presentations.update_presentation_state(
        Claper.Repo.get_by!(Claper.Presentations.PresentationState,
          presentation_file_id: presentation_file.id
        ),
        %{poll_visible: true}
      )

    state
  end

  describe "the link does not outlive the event" do
    test "ending the event disconnects an open embed", %{conn: conn, event: event, token: token} do
      {:ok, view, _html} = live(conn, ~p"/embed/presenter/#{token}")

      {:ok, _event} = Claper.Events.terminate_event(event)

      # Deleting nothing and revoking nothing: the event simply ended, and a
      # frame that keeps rendering the room after that is the case the module
      # doc promises cannot happen.
      assert_redirect(view, "/embed/presenter/ended")
    end

    test "revoking disconnects an open embed", %{
      conn: conn,
      user: user,
      event: event,
      token: token
    } do
      {:ok, view, _html} = live(conn, ~p"/embed/presenter/#{token}")

      {:ok, 1} = Claper.Events.revoke_presenter_embed_tokens(event, user)

      assert_redirect(view, "/embed/presenter/ended")
    end

    test "replacing the link disconnects the frame on the old one", %{
      conn: conn,
      user: user,
      event: event,
      token: token
    } do
      {:ok, view, _html} = live(conn, ~p"/embed/presenter/#{token}")

      {:ok, _new_token} = Claper.Events.create_presenter_embed_token(event, user)

      assert_redirect(view, "/embed/presenter/ended")
    end

    test "the socket does not keep the raw token", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/embed/presenter/#{token}")

      assigns = :sys.get_state(view.pid).socket.assigns

      refute Map.has_key?(assigns, :presenter_embed_token)

      refute assigns
             |> Map.values()
             |> Enum.any?(fn value -> is_binary(value) and value == token end)
    end
  end

  describe "frame headers" do
    test "the embed route ships the configured frame-ancestors allow list", %{
      conn: conn,
      token: token
    } do
      previous = Application.get_env(:claper, :presenter_embed_frame_ancestors)

      Application.put_env(
        :claper,
        :presenter_embed_frame_ancestors,
        "https://*.officeapps.live.com"
      )

      on_exit(fn -> Application.put_env(:claper, :presenter_embed_frame_ancestors, previous) end)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert get_resp_header(conn, "x-frame-options") == []

      assert get_resp_header(conn, "content-security-policy") == [
               "frame-ancestors 'self' https://*.officeapps.live.com"
             ]
    end

    test "framing is off by default", %{conn: conn, token: token} do
      previous = Application.get_env(:claper, :presenter_embed_frame_ancestors)
      Application.delete_env(:claper, :presenter_embed_frame_ancestors)
      on_exit(fn -> Application.put_env(:claper, :presenter_embed_frame_ancestors, previous) end)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'none'"]
    end

    test "a configured value cannot append a second CSP directive", %{conn: conn, token: token} do
      previous = Application.get_env(:claper, :presenter_embed_frame_ancestors)

      Application.put_env(
        :claper,
        :presenter_embed_frame_ancestors,
        "https://example.com; default-src *"
      )

      on_exit(fn -> Application.put_env(:claper, :presenter_embed_frame_ancestors, previous) end)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      # The whole value has to fall back, not just the offending source.
      # Filtering source by source used to keep "default-src *", which allows
      # every origin to frame the page, so the earlier assertions on the
      # absence of ";" and of the origin passed while access was wide open.
      assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'none'"]
    end

    # Each of these is valid CSP and each means "anyone", which an allow list
    # must never produce by accident. They contain no forbidden character, so
    # the character class alone lets them through.
    for value <- [
          "*",
          "https://a.com *",
          "https:",
          "//evil.com",
          "https://*",
          "http://*",
          "*:443"
        ] do
      test "a source that names no host falls back: #{value}", %{conn: conn, token: token} do
        previous = Application.get_env(:claper, :presenter_embed_frame_ancestors)
        Application.put_env(:claper, :presenter_embed_frame_ancestors, unquote(value))

        on_exit(fn ->
          Application.put_env(:claper, :presenter_embed_frame_ancestors, previous)
        end)

        conn = get(conn, ~p"/embed/presenter/#{token}")

        assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'none'"]
      end
    end

    test "a subdomain wildcard still names a host and is kept", %{conn: conn, token: token} do
      previous = Application.get_env(:claper, :presenter_embed_frame_ancestors)

      Application.put_env(
        :claper,
        :presenter_embed_frame_ancestors,
        "https://*.officeapps.live.com"
      )

      on_exit(fn -> Application.put_env(:claper, :presenter_embed_frame_ancestors, previous) end)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert get_resp_header(conn, "content-security-policy") == [
               "frame-ancestors 'self' https://*.officeapps.live.com"
             ]
    end

    test "a revoked link answers 404 that a foreign frame can still display", %{
      conn: conn,
      user: user,
      event: event,
      token: token
    } do
      previous = Application.get_env(:claper, :presenter_embed_frame_ancestors)

      Application.put_env(
        :claper,
        :presenter_embed_frame_ancestors,
        "https://*.officeapps.live.com"
      )

      on_exit(fn -> Application.put_env(:claper, :presenter_embed_frame_ancestors, previous) end)

      {:ok, _count} = Claper.Events.revoke_presenter_embed_tokens(event, user)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert response(conn, 404)
      assert get_resp_header(conn, "x-frame-options") == []

      assert get_resp_header(conn, "content-security-policy") == [
               "frame-ancestors 'self' https://*.officeapps.live.com"
             ]
    end

    test "the regular presenter route keeps x-frame-options", %{
      conn: conn,
      user: user,
      event: event
    } do
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/e/#{event.code}/presenter")

      assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
      assert get_resp_header(conn, "content-security-policy") == []
    end
  end
end
