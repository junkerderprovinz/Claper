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
      xml = conn |> get("/addin/manifest/sidebar.xml") |> response(200)

      assert xml =~ "#{host}/claper/addin/sidebar.html"
      refute xml =~ "#{host}/addin/sidebar.html"

      # AppDomains still wants the bare origin, without the prefix.
      assert xml =~ "<AppDomain>#{host}</AppDomain>"
    end

    test "are served as xml", %{conn: conn} do
      conn = get(conn, ~p"/addin/manifest/sidebar.xml")

      assert conn |> get_resp_header("content-type") |> hd() =~ "application/xml"
      assert conn |> get_resp_header("content-disposition") |> hd() =~ "claper-sidebar.xml"
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

  describe "the page" do
    test "offers both manifests by their own address", %{conn: conn, host: host} do
      html = conn |> get(~p"/addin") |> html_response(200)

      assert html =~ "#{host}/addin/manifest/sidebar.xml"
      assert html =~ "#{host}/addin/manifest/slide.xml"
    end

    test "does not hand out any key", %{conn: conn} do
      html = conn |> get(~p"/addin") |> html_response(200)

      # It is a public page. The writing key is created in the event's settings
      # and must never be printed somewhere unauthenticated.
      refute html =~ "Bearer"
      assert html =~ "settings"
    end

    test "is gone when the feature is switched off, as a page rather than json", %{conn: conn} do
      Application.delete_env(:claper, :presenter_embed_frame_ancestors)

      body = conn |> get(~p"/addin") |> response(404)

      refute body =~ ~s({"error")
    end
  end
end
