defmodule ClaperWeb.AddinManifestControllerTest do
  use ClaperWeb.ConnCase

  setup do
    previous = Application.get_env(:claper, :presenter_embed_frame_ancestors)
    Application.put_env(:claper, :presenter_embed_frame_ancestors, "https://slides.example.com")

    on_exit(fn ->
      if previous do
        Application.put_env(:claper, :presenter_embed_frame_ancestors, previous)
      else
        Application.delete_env(:claper, :presenter_embed_frame_ancestors)
      end
    end)

    %{host: ClaperWeb.Endpoint.url()}
  end

  describe "the manifests" do
    # An Office manifest carries its address as a fixed string, so each server
    # renders its own.
    test "carry this server's address and no placeholder", %{conn: conn, host: host} do
      for path <- [~p"/addin/manifest/sidebar.xml", ~p"/addin/manifest/slide.xml"] do
        xml = conn |> get(path) |> response(200)

        refute xml =~ "claper.example.com"
        assert xml =~ host
      end
    end

    test "name this server's add-in pages", %{conn: conn, host: host} do
      sidebar = conn |> get(~p"/addin/manifest/sidebar.xml") |> response(200)
      slide = conn |> get(~p"/addin/manifest/slide.xml") |> response(200)

      assert sidebar =~ "#{host}/addin/sidebar.html"
      assert slide =~ "#{host}/addin/slide.html"
      assert sidebar =~ "<AppDomain>#{host}</AppDomain>"
    end

    test "are a task pane and a content add-in", %{conn: conn} do
      sidebar = conn |> get(~p"/addin/manifest/sidebar.xml") |> response(200)
      slide = conn |> get(~p"/addin/manifest/slide.xml") |> response(200)

      assert sidebar =~ ~s(xsi:type="TaskPaneApp")
      assert slide =~ ~s(xsi:type="ContentApp")
      refute sidebar =~ ~s(xsi:type="ContentApp")
    end

    # A manifest that ignores the prefix points one directory too high, and
    # Office then loads nothing without a useful error.
    test "follow a path prefix into the page addresses", %{conn: conn} do
      original = Application.get_env(:claper, ClaperWeb.Endpoint)

      on_exit(fn ->
        Application.put_env(:claper, ClaperWeb.Endpoint, original)
        ClaperWeb.Endpoint.config_change([{ClaperWeb.Endpoint, original}], [])
      end)

      prefixed =
        Keyword.put(
          original,
          :url,
          Keyword.put(Keyword.get(original, :url, []), :path, "/claper")
        )

      Application.put_env(:claper, ClaperWeb.Endpoint, prefixed)
      ClaperWeb.Endpoint.config_change([{ClaperWeb.Endpoint, prefixed}], [])

      host = ClaperWeb.Endpoint.url()
      sidebar = conn |> get("/addin/manifest/sidebar.xml") |> response(200)
      slide = conn |> get("/addin/manifest/slide.xml") |> response(200)
      page = conn |> get("/addin") |> html_response(200)

      assert sidebar =~ "#{host}/claper/addin/sidebar.html"
      assert sidebar =~ "#{host}/claper/images/favicon.png"
      assert slide =~ "#{host}/claper/addin/slide.html"
      assert page =~ "#{host}/claper/addin/manifest/sidebar.xml"

      refute sidebar =~ "#{host}/addin/sidebar.html"
      refute slide =~ "#{host}/addin/slide.html"

      # AppDomains takes the bare origin, without the prefix.
      assert sidebar =~ "<AppDomain>#{host}</AppDomain>"
    end

    test "are served as xml downloads", %{conn: conn} do
      for {path, filename} <- [
            {~p"/addin/manifest/sidebar.xml", "claper-sidebar.xml"},
            {~p"/addin/manifest/slide.xml", "claper-on-a-slide.xml"}
          ] do
        conn = get(conn, path)

        assert conn |> get_resp_header("content-type") |> hd() =~ "application/xml"
        assert conn |> get_resp_header("content-disposition") |> hd() =~ filename
      end
    end

    # The Microsoft 365 admin center fetches the manifest itself, and Phoenix
    # picks the format from the Accept header rather than the ".xml" in the path.
    test "are served to a client that asks for xml", %{conn: conn} do
      xml =
        conn
        |> put_req_header("accept", "application/xml")
        |> get(~p"/addin/manifest/sidebar.xml")
        |> response(200)

      assert xml =~ "<OfficeApp"
    end

    # The template comments are meant for whoever edits them in the repository.
    test "carry none of the repository's editing notes", %{conn: conn} do
      for path <- [~p"/addin/manifest/sidebar.xml", ~p"/addin/manifest/slide.xml"] do
        xml = conn |> get(path) |> response(200)

        refute xml =~ "<!--"
        refute xml =~ "Replace every"
        refute xml =~ "README"
      end
    end

    # The Microsoft 365 admin center fetches this URL without a session.
    test "are readable without a session", %{conn: conn} do
      assert conn |> get(~p"/addin/manifest/sidebar.xml") |> response(200)
    end

    test "are gone when the feature is switched off", %{conn: conn} do
      Application.delete_env(:claper, :presenter_embed_frame_ancestors)

      assert conn |> get(~p"/addin/manifest/sidebar.xml") |> response(404)
      assert conn |> get(~p"/addin/manifest/slide.xml") |> response(404)
    end
  end

  describe "the add-in's own words" do
    # The add-in pages are static files and cannot use gettext, so they fetch
    # their strings from here.
    test "cover every known locale", %{conn: conn} do
      body = conn |> get(~p"/addin/strings.json") |> json_response(200)

      for locale <- Gettext.known_locales(ClaperWeb.Gettext) do
        assert Map.has_key?(body, locale), "missing #{locale}"
      end
    end

    # English is the key as well as the fallback, so an untranslated string
    # still reads as a sentence.
    test "are keyed by the English text", %{conn: conn} do
      body = conn |> get(~p"/addin/strings.json") |> json_response(200)

      assert body["en"]["Create poll"] == "Create poll"
      assert body["de"]["Create poll"] == "Umfrage anlegen"
    end

    test "include phrases from both pages", %{conn: conn} do
      body = conn |> get(~p"/addin/strings.json") |> json_response(200)
      english = body["en"]

      # "answers so far" is built by the script rather than written in the markup.
      for phrase <- [
            "Bring Claper into PowerPoint",
            "Put the code on this slide",
            "Claper on this slide",
            "Show on this slide",
            "answers so far"
          ] do
        assert Map.has_key?(english, phrase), "not translatable: #{phrase}"
      end
    end

    test "are gone when the feature is switched off", %{conn: conn} do
      Application.delete_env(:claper, :presenter_embed_frame_ancestors)

      assert conn |> get(~p"/addin/strings.json") |> response(404)
    end
  end

  describe "the page" do
    test "offers both manifests by their own address", %{conn: conn, host: host} do
      html = conn |> get(~p"/addin") |> html_response(200)

      assert html =~ "#{host}/addin/manifest/sidebar.xml"
      assert html =~ "#{host}/addin/manifest/slide.xml"
    end

    test "does not hand out any key", %{conn: conn} do
      user = Claper.AccountsFixtures.user_fixture()
      file = Claper.PresentationsFixtures.presentation_file_fixture(%{user: user}, [:event])
      event = Claper.Events.get_event_with_code(file.event.code)

      {:ok, addin_token} = Claper.Events.create_addin_token(event, user)
      {:ok, embed_token} = Claper.Events.create_presenter_embed_token(event, user)

      html = conn |> get(~p"/addin") |> html_response(200)

      refute html =~ addin_token
      refute html =~ embed_token
      refute html =~ event.code
    end

    test "is an html 404 page when the feature is switched off", %{conn: conn} do
      Application.delete_env(:claper, :presenter_embed_frame_ancestors)

      conn = get(conn, ~p"/addin")
      body = html_response(conn, 404)

      assert body =~ "<title>Not found - Claper</title>"
      refute body =~ ~s({"error")
    end
  end

  # The installed manifest points at these pages by a fixed name, so a cached
  # copy would outlive every update until the add-in is reinstalled.
  describe "the add-in pages are revalidated rather than kept" do
    setup %{conn: conn} do
      Application.put_env(:claper, :presenter_embed_frame_ancestors, ["https://example.test"])
      on_exit(fn -> Application.delete_env(:claper, :presenter_embed_frame_ancestors) end)
      %{conn: conn}
    end

    for page <- ~w(sidebar.html slide.html) do
      test "#{page} says no-cache", %{conn: conn} do
        conn = get(conn, "/addin/#{unquote(page)}")

        assert conn.status == 200
        assert get_resp_header(conn, "cache-control") == ["no-cache"]
        # The ETag lets most revalidations end in a 304.
        assert [_etag] = get_resp_header(conn, "etag")
      end
    end

    test "other static files keep the public cache header", %{conn: conn} do
      conn = get(conn, "/images/favicon.png")

      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["public"]
    end
  end
end
