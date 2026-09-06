defmodule ClaperWeb.EventLive.PresenterEmbedTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{AccountsFixtures, PresentationsFixtures}

  setup do
    user = user_fixture()
    presentation_file = presentation_file_fixture(%{user: user}, [:event])
    presentation_state_fixture(%{presentation_file: presentation_file})
    event = Claper.Events.get_event_with_code(presentation_file.event.code)

    {:ok, token} = Claper.Events.create_presenter_embed_token(event, user)

    %{user: user, event: event, token: token, presentation_file: presentation_file}
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
      poll =
        Claper.PollsFixtures.poll_fixture(%{
          presentation_file_id: presentation_file.id,
          position: 0,
          title: "counted poll",
          show_results: false
        })

      {:ok, _state} =
        Claper.Presentations.update_presentation_state(
          Claper.Repo.get_by!(Claper.Presentations.PresentationState,
            presentation_file_id: presentation_file.id
          ),
          %{poll_visible: true}
        )

      html = get(conn, ~p"/embed/presenter/#{token}") |> html_response(200)

      assert html =~ "counted poll"
      refute html =~ "% (0)"

      assert poll.show_results == false
    end
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
      previous = Application.get_env(:claper, :embed_frame_ancestors)
      Application.put_env(:claper, :embed_frame_ancestors, "https://*.officeapps.live.com")
      on_exit(fn -> Application.put_env(:claper, :embed_frame_ancestors, previous) end)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert get_resp_header(conn, "x-frame-options") == []

      assert get_resp_header(conn, "content-security-policy") == [
               "frame-ancestors https://*.officeapps.live.com"
             ]
    end

    test "framing is off by default", %{conn: conn, token: token} do
      previous = Application.get_env(:claper, :embed_frame_ancestors)
      Application.delete_env(:claper, :embed_frame_ancestors)
      on_exit(fn -> Application.put_env(:claper, :embed_frame_ancestors, previous) end)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'none'"]
    end

    test "a configured value cannot append a second CSP directive", %{conn: conn, token: token} do
      previous = Application.get_env(:claper, :embed_frame_ancestors)

      Application.put_env(
        :claper,
        :embed_frame_ancestors,
        "https://example.com; default-src *"
      )

      on_exit(fn -> Application.put_env(:claper, :embed_frame_ancestors, previous) end)

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
        previous = Application.get_env(:claper, :embed_frame_ancestors)
        Application.put_env(:claper, :embed_frame_ancestors, unquote(value))
        on_exit(fn -> Application.put_env(:claper, :embed_frame_ancestors, previous) end)

        conn = get(conn, ~p"/embed/presenter/#{token}")

        assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'none'"]
      end
    end

    test "a subdomain wildcard still names a host and is kept", %{conn: conn, token: token} do
      previous = Application.get_env(:claper, :embed_frame_ancestors)
      Application.put_env(:claper, :embed_frame_ancestors, "https://*.officeapps.live.com")
      on_exit(fn -> Application.put_env(:claper, :embed_frame_ancestors, previous) end)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert get_resp_header(conn, "content-security-policy") == [
               "frame-ancestors https://*.officeapps.live.com"
             ]
    end

    test "a revoked link answers 404 that a foreign frame can still display", %{
      conn: conn,
      user: user,
      event: event,
      token: token
    } do
      previous = Application.get_env(:claper, :embed_frame_ancestors)
      Application.put_env(:claper, :embed_frame_ancestors, "https://*.officeapps.live.com")
      on_exit(fn -> Application.put_env(:claper, :embed_frame_ancestors, previous) end)

      {:ok, _count} = Claper.Events.revoke_presenter_embed_tokens(event, user)

      conn = get(conn, ~p"/embed/presenter/#{token}")

      assert response(conn, 404)
      assert get_resp_header(conn, "x-frame-options") == []

      assert get_resp_header(conn, "content-security-policy") == [
               "frame-ancestors https://*.officeapps.live.com"
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
