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
    # The whole reason these are served rather than committed and copied: an
    # Office manifest carries its address as a fixed string, so a file naming
    # somebody else's server is worse than no file.
    test "carry this server's address and no placeholder", %{conn: conn, host: host} do
      for path <- [~p"/addin/manifest/sidebar.xml", ~p"/addin/manifest/slide.xml"] do
        xml = conn |> get(path) |> response(200)

        refute xml =~ "claper.example.com"
        assert xml =~ host
      end
    end

    test "name the pages that actually exist here", %{conn: conn, host: host} do
      sidebar = conn |> get(~p"/addin/manifest/sidebar.xml") |> response(200)
      slide = conn |> get(~p"/addin/manifest/slide.xml") |> response(200)

      assert sidebar =~ "#{host}/addin/sidebar.html"
      assert slide =~ "#{host}/addin/slide.html"

      # And the origin on its own, which is what AppDomains needs.
      assert sidebar =~ "<AppDomain>#{host}</AppDomain>"
    end

    test "are the two different kinds, which Office needs one file each for", %{conn: conn} do
      sidebar = conn |> get(~p"/addin/manifest/sidebar.xml") |> response(200)
      slide = conn |> get(~p"/addin/manifest/slide.xml") |> response(200)

      assert sidebar =~ ~s(xsi:type="TaskPaneApp")
      assert slide =~ ~s(xsi:type="ContentApp")
      refute sidebar =~ ~s(xsi:type="ContentApp")
    end

    # The reason the page addresses are built through the endpoint instead of
    # one flat substitution. A Claper published under a prefix would otherwise
    # get a manifest pointing one directory too high, and Office would load
    # nothing with no useful error.
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

      # Every address that names a page has to move under the prefix, and each
      # is a separate substitution, so each is checked.
      assert sidebar =~ "#{host}/claper/addin/sidebar.html"
      assert sidebar =~ "#{host}/claper/images/favicon.png"
      assert slide =~ "#{host}/claper/addin/slide.html"
      assert page =~ "#{host}/claper/addin/manifest/sidebar.xml"

      refute sidebar =~ "#{host}/addin/sidebar.html"
      refute slide =~ "#{host}/addin/slide.html"

      # AppDomains still wants the bare origin, without the prefix.
      assert sidebar =~ "<AppDomain>#{host}</AppDomain>"
    end

    test "are served as xml, both of them", %{conn: conn} do
      for {path, filename} <- [
            {~p"/addin/manifest/sidebar.xml", "claper-sidebar.xml"},
            {~p"/addin/manifest/slide.xml", "claper-on-a-slide.xml"}
          ] do
        conn = get(conn, path)

        assert conn |> get_resp_header("content-type") |> hd() =~ "application/xml"
        assert conn |> get_resp_header("content-disposition") |> hd() =~ filename
      end
    end

    # The one caller this route exists for is the Microsoft 365 admin center,
    # which fetches the URL itself. Phoenix picks the format from the Accept
    # header rather than from the ".xml" in the path, so a pipeline accepting
    # only "html" would answer 406 to exactly that client.
    test "are served to a client that asks for xml", %{conn: conn} do
      xml =
        conn
        |> put_req_header("accept", "application/xml")
        |> get(~p"/addin/manifest/sidebar.xml")
        |> response(200)

      assert xml =~ "<OfficeApp"
    end

    # They are downloaded and handed to Office, not read by a person, and the
    # comments in the templates address whoever edits them in the repository.
    test "carry none of the repository's editing notes", %{conn: conn} do
      for path <- [~p"/addin/manifest/sidebar.xml", ~p"/addin/manifest/slide.xml"] do
        xml = conn |> get(path) |> response(200)

        refute xml =~ "<!--"
        refute xml =~ "Replace every"
        refute xml =~ "README"
      end
    end

    # The Microsoft 365 admin center fetches this URL itself and is not logged
    # in. A login here would break the one route that makes installing a paste.
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
    # The two add-in pages are static files and cannot render gettext, which is
    # why they were English whatever Claper was set to. They fetch this instead.
    test "come in every language Claper speaks", %{conn: conn} do
      body = conn |> get(~p"/addin/strings.json") |> json_response(200)

      for locale <- Gettext.known_locales(ClaperWeb.Gettext) do
        assert Map.has_key?(body, locale), "missing #{locale}"
      end
    end

    # English is the key as well as the fallback, so a string nobody has
    # translated yet still reads as a sentence rather than as an identifier.
    test "are keyed by their own English", %{conn: conn} do
      body = conn |> get(~p"/addin/strings.json") |> json_response(200)

      assert body["en"]["Create poll"] == "Create poll"
      assert body["de"]["Create poll"] == "Umfrage anlegen"
    end

    test "cover what the pages actually say", %{conn: conn} do
      body = conn |> get(~p"/addin/strings.json") |> json_response(200)
      english = body["en"]

      # A handful drawn from both pages, including one the script builds rather
      # than one sitting in the markup.
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

    # It is a public page. An earlier version of this test only refused the word
    # "Bearer", which appears nowhere in any rendered page and so could never
    # fail. This one puts a real key into the database first.
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

    # Asserting what the body is not would pass on an empty one, so this names
    # what it has to be: Claper's own 404 page, not the JSON the API routes get.
    test "is gone when the feature is switched off, as a page rather than json", %{conn: conn} do
      Application.delete_env(:claper, :presenter_embed_frame_ancestors)

      conn = get(conn, ~p"/addin")
      body = html_response(conn, 404)

      assert body =~ "<title>Not found - Claper</title>"
      refute body =~ ~s({"error")
    end
  end

  # Everything else under priv/static carries a content hash in its name, so a
  # browser may keep it forever. The add-in's two pages cannot: the manifest
  # installed in Office points at them by name and cannot be re-pointed without
  # reinstalling the add-in. Served with the default "public" and no expiry,
  # Office kept a copy and went on showing text the file no longer contained -
  # which read as "the fix did not work" through several rounds of fixing.
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
        # The ETag is what makes no-cache cheap: the browser asks, and almost
        # every answer is a 304 with nothing but headers in it.
        assert [_etag] = get_resp_header(conn, "etag")
      end
    end

    # The hashed assets must keep their long cache. A fix that made everything
    # revalidate would be a different bug wearing this one's clothes.
    test "a hashed asset is still cached for as long as the browser likes", %{conn: conn} do
      conn = get(conn, "/images/favicon.png")

      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["public"]
    end
  end
end
