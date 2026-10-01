defmodule ClaperWeb.EventLive.PresenterEmbedTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{AccountsFixtures, PresentationsFixtures}

  setup do
    # Embedding stays off until the frame-ancestors allow list is configured.
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

      {:ok, _state} = Claper.Presentations.update_presentation_state(state, %{"position" => 3})

      html = render(view)
      assert html =~ "/uploads/123456/4.jpg"
      refute html =~ "/uploads/123456/1.jpg"
    end

    test "the owner's presenter view carries the whole deck", %{
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
    # The embed route needs no login, so it stays read-only only while these
    # modules handle no client events.
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

    # Anyone with the event code can post and vote at /e/:code without an
    # account, so the join screen must not be rendered at all.
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

    test "the regular presenter route shows the join screen", %{
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

    # The presenter view only fades a hidden poll out, which is fine for the
    # logged in owner but not for markup anyone with the link can read.
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

    test "a visible poll is shown in the embed", %{
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

    # The quiz overlay marks the correct answer and is only faded out while the
    # results are hidden.
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

    # An embed counts as an attendee device for attendee_visibility.
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

    test "poll results the owner hid are absent from the embed", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      # Unequal votes, so the bar width differs between hidden and shown results.
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

    # The block sits on a transparent background, so white text would vanish on
    # a white slide.
    test "the default text is dark and has no card behind it", %{
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

      assert poll_block =~ "text-gray-900"
      refute poll_block =~ "text-white"
      refute poll_block =~ "bg-white", "the default should have no card"
    end

    # Unknown values fall back to the readable default, so a hand-edited or
    # truncated link cannot produce an invisible block.
    test "the link sets the card, theme, corners and shadow", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        title: "styled poll",
        show_results: true
      })

      show_poll(presentation_file)

      block = fn query ->
        get(conn, "/embed/interaction/#{token}#{query}")
        |> html_response(200)
        |> String.split(~s(id="poll"))
        |> Enum.at(1)
        |> String.slice(0, 1400)
      end

      default = block.("")
      refute default =~ "bg-white/95"
      assert default =~ "text-gray-900"
      assert default =~ "rounded-md"
      refute default =~ "shadow-lg"

      carded = block.("?panel=on&theme=dark&radius=sharp&shadow=on")
      assert carded =~ "bg-gray-900/95"
      assert carded =~ "text-white"
      assert carded =~ "rounded-none"
      assert carded =~ "shadow-lg"

      nonsense = block.("?theme=neon&panel=maybe&radius=blob&shadow=yes")
      refute nonsense =~ "bg-white/95"
      assert nonsense =~ "text-gray-900"
      assert nonsense =~ "rounded-md"
    end

    test "the link can set custom text and bar colours", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        title: "coloured poll",
        show_results: true
      })

      show_poll(presentation_file)

      page = fn query ->
        get(conn, "/embed/interaction/#{token}#{query}") |> html_response(200)
      end

      chosen = page.("?text=%23ff8800&bar=112233")
      assert chosen =~ ".claper-ink { color: #ff8800 !important; }"
      assert chosen =~ ".claper-bar { background-color: #112233 !important; }"

      # The value is written into a stylesheet, so only six hex digits are taken.
      refute page.("?text=red;}body{display:none") =~ "claper-ink { color"
      refute page.("?bar=<script>") =~ "claper-bar { background"
      refute page.("") =~ "claper-ink { color"
    end

    test "an open question shows its wording and the answers as they arrive", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      form =
        Claper.FormsFixtures.form_fixture(%{
          presentation_file_id: presentation_file.id,
          position: 0,
          title: "what should we build",
          fields: [%{name: "Your answer", type: "text"}]
        })

      empty = get(conn, "/embed/interaction/#{token}?form=#{form.id}") |> html_response(200)
      assert empty =~ "what should we build"
      assert empty =~ "Waiting for the first answer"

      Claper.Forms.create_form_submit(%{
        "form_id" => form.id,
        "attendee_identifier" => "someone",
        "response" => %{"Your answer" => "a bigger boat"}
      })

      answered = get(conn, "/embed/interaction/#{token}?form=#{form.id}") |> html_response(200)
      assert answered =~ "a bigger boat"
      refute answered =~ "Waiting for the first answer"
    end

    test "pinning an open question hides the current poll", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        title: "the poll on this page"
      })

      form =
        Claper.FormsFixtures.form_fixture(%{
          presentation_file_id: presentation_file.id,
          position: 0,
          title: "the open question"
        })

      show_poll(presentation_file)

      html = get(conn, "/embed/interaction/#{token}?form=#{form.id}") |> html_response(200)

      assert html =~ "the open question"
      refute html =~ "the poll on this page"
    end

    test "pinning an open question hides the current quiz", %{
      conn: conn,
      token: token,
      presentation_file: presentation_file
    } do
      Claper.QuizzesFixtures.quiz_fixture(%{
        presentation_file: presentation_file,
        position: 0,
        enabled: true,
        show_results: true,
        title: "the quiz on this page"
      })

      form =
        Claper.FormsFixtures.form_fixture(%{
          presentation_file_id: presentation_file.id,
          position: 0,
          title: "the open question"
        })

      html = get(conn, "/embed/interaction/#{token}?form=#{form.id}") |> html_response(200)

      assert html =~ "the open question"
      refute html =~ "some question content"
      refute html =~ "option 1"
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
    # The embed is the same page for everyone holding the link.
    test "the embed ignores a logged in visitor's session", %{
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
    # The "presenter" visibility means the screen in the room only.
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

      # The whole value falls back, since dropping only the bad source would
      # keep "default-src *".
      assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'none'"]
    end

    # Each of these is valid CSP that allows any host, and none contains a
    # character the sanitiser rejects.
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

    test "a subdomain wildcard names a host and is kept", %{conn: conn, token: token} do
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

    test "a revoked link answers 404 with the allow list header", %{
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

  describe "the joining block" do
    # A deck that keeps its own slides never projects Claper's joining screen.
    test "carries the code and a QR code when the link asks for it", %{
      conn: conn,
      token: token,
      event: event
    } do
      html = get(conn, ~p"/embed/interaction/#{token}?show=join") |> html_response(200)

      assert html =~ String.upcase(event.code)
      assert html =~ ~s(phx-hook="QRCode")
      assert html =~ ~s(data-code="#{event.code}")
    end

    # The event code lets anyone post and vote, so only the joining block shows it.
    test "the code stays out of every other embedded view", %{
      conn: conn,
      token: token,
      event: event
    } do
      for path <- [
            ~p"/embed/interaction/#{token}",
            ~p"/embed/interaction/#{token}?show=messages",
            ~p"/embed/presenter/#{token}"
          ] do
        refute get(conn, path) |> html_response(200) =~ String.upcase(event.code)
      end
    end

    test "an unknown show falls back to the interaction", %{
      conn: conn,
      token: token,
      event: event
    } do
      html = get(conn, ~p"/embed/interaction/#{token}?show=nonsense") |> html_response(200)

      refute html =~ String.upcase(event.code)
    end

    # The Presenter hook throws without a #slider, which keeps the QRCode hook
    # from mounting.
    test "does not mount the deck hook", %{
      conn: conn,
      token: token
    } do
      interaction = get(conn, ~p"/embed/interaction/#{token}?show=join") |> html_response(200)
      deck = get(conn, ~p"/embed/presenter/#{token}") |> html_response(200)

      refute interaction =~ ~s(phx-hook="Presenter")
      assert interaction =~ ~s(phx-hook="QRCode")
      assert deck =~ ~s(phx-hook="Presenter")
    end
  end

  describe "the messages block" do
    test "shows the audience's messages when the link asks for them", %{
      conn: conn,
      token: token,
      event: event,
      presentation_file: presentation_file
    } do
      Claper.PostsFixtures.post_fixture(%{event: event, body: "a question from the room"})

      {:ok, _state} =
        Claper.Presentations.update_presentation_state(
          Claper.Repo.get_by!(Claper.Presentations.PresentationState,
            presentation_file_id: presentation_file.id
          ),
          %{chat_visible: true}
        )

      html = get(conn, ~p"/embed/interaction/#{token}?show=messages") |> html_response(200)

      assert html =~ "a question from the room"
    end

    test "hiding the chat empties the block", %{
      conn: conn,
      token: token,
      event: event,
      presentation_file: presentation_file
    } do
      Claper.PostsFixtures.post_fixture(%{event: event, body: "a hidden message"})

      {:ok, _state} =
        Claper.Presentations.update_presentation_state(
          Claper.Repo.get_by!(Claper.Presentations.PresentationState,
            presentation_file_id: presentation_file.id
          ),
          %{chat_visible: false}
        )

      html = get(conn, ~p"/embed/interaction/#{token}?show=messages") |> html_response(200)

      refute html =~ "a hidden message"
    end
  end

  describe "a quiz on an embedded slide" do
    setup %{presentation_file: presentation_file} do
      quiz =
        Claper.QuizzesFixtures.quiz_fixture(%{
          presentation_file: presentation_file,
          presentation_file_id: presentation_file.id,
          title: "pinned quiz",
          show_results: false,
          quiz_questions: [
            %{
              content: "Capital of France?",
              type: "qcm",
              quiz_question_opts: [
                %{content: "Paris", is_correct: true},
                %{content: "Lyon", is_correct: false}
              ]
            }
          ]
        })

      %{quiz: quiz}
    end

    test "shows the question and its answers", %{conn: conn, token: token, quiz: quiz} do
      html = get(conn, ~p"/embed/interaction/#{token}?quiz=#{quiz.id}") |> html_response(200)

      assert html =~ "Capital of France?"
      assert html =~ "Paris"
      assert html =~ "Lyon"
    end

    test "does not mark the right answer before the results are released", %{
      conn: conn,
      token: token,
      quiz: quiz
    } do
      html = get(conn, ~p"/embed/interaction/#{token}?quiz=#{quiz.id}") |> html_response(200)

      refute html =~ "bg-green-600"
      refute html =~ "response_count"
      refute html =~ "% ("
    end

    test "marks the right answer after the results are released", %{
      conn: conn,
      token: token,
      quiz: quiz,
      event: event
    } do
      {:ok, _quiz} = Claper.Quizzes.update_quiz(event.uuid, quiz, %{show_results: true})

      html = get(conn, ~p"/embed/interaction/#{token}?quiz=#{quiz.id}") |> html_response(200)

      assert html =~ "bg-green-600"
    end

    test "a quiz of another event is not shown", %{conn: conn, token: token} do
      other_user = user_fixture()
      other_file = presentation_file_fixture(%{user: other_user}, [:event])

      foreign =
        Claper.QuizzesFixtures.quiz_fixture(%{
          presentation_file: other_file,
          presentation_file_id: other_file.id,
          title: "someone else's quiz"
        })

      html = get(conn, ~p"/embed/interaction/#{token}?quiz=#{foreign.id}") |> html_response(200)

      refute html =~ "someone else's quiz"
    end

    test "pinning a quiz does not let the deck's poll through", %{
      conn: conn,
      token: token,
      quiz: quiz,
      presentation_file: presentation_file
    } do
      Claper.PollsFixtures.poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        title: "the deck's own poll",
        show_results: true
      })

      show_poll(presentation_file)

      html = get(conn, ~p"/embed/interaction/#{token}?quiz=#{quiz.id}") |> html_response(200)

      refute html =~ "the deck's own poll"
    end
  end

  # PowerPoint paints an opaque background under a web object, so the block
  # paints the slide's colour, taken from the link.
  describe "embed_background/2" do
    alias ClaperWeb.EventLive.Presenter

    test "the projected deck is black, whatever the link says" do
      assert Presenter.embed_background(false, %{bg: "#ff0000"}) == "black"
    end

    test "an embed with no colour named stays transparent" do
      assert Presenter.embed_background(true, %{bg: nil}) == "transparent"
    end

    test "an embed paints the colour the link names" do
      assert Presenter.embed_background(true, %{bg: "#102030"}) == "#102030"
    end

    # Some render paths run before the style map is assigned.
    test "a missing style map falls back to transparent" do
      assert Presenter.embed_background(true, nil) == "transparent"
    end
  end

  # The value comes from the link and is written into a stylesheet.
  describe "embed_style/1 and the background colour" do
    alias ClaperWeb.EventLive.Presenter

    test "six hex digits are taken, with or without the hash" do
      assert Presenter.embed_style(%{"bg" => "#AABBCC"}).bg == "#aabbcc"
      assert Presenter.embed_style(%{"bg" => "aabbcc"}).bg == "#aabbcc"
    end

    test "anything that is not exactly a colour is no colour" do
      assert Presenter.embed_style(%{"bg" => "red; } body { display: none"}).bg == nil
      assert Presenter.embed_style(%{"bg" => "#abc"}).bg == nil
      assert Presenter.embed_style(%{}).bg == nil
    end
  end

  describe "poll_tally/3" do
    alias ClaperWeb.EventLive.Presenter

    test "shows the format the link asks for" do
      assert Presenter.poll_tally(67, 2, "both") == "67% (2)"
      assert Presenter.poll_tally(67, 2, "percent") == "67%"
      assert Presenter.poll_tally(67, 2, "count") == "2"
    end

    test "an unknown or missing choice falls back to both" do
      assert Presenter.poll_tally(50, 1, "nonsense") == "50% (1)"
      assert Presenter.poll_tally(50, 1, nil) == "50% (1)"
      assert Presenter.embed_style(%{}).counts == "both"
      assert Presenter.embed_style(%{"counts" => "sideways"}).counts == "both"
      assert Presenter.embed_style(%{"counts" => "count"}).counts == "count"
    end
  end
end
