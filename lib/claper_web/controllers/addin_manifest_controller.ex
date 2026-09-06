defmodule ClaperWeb.AddinManifestController do
  @moduledoc """
  Hands out this server's own PowerPoint manifests, and the page that explains
  what to do with them.

  An Office manifest carries the add-in's address as a fixed string, and the API
  it talks to sends no CORS headers, so one add-in hosted somewhere central
  cannot serve a self-hosted Claper. Every instance needs manifests naming
  itself. Without this the instructions end at "open both files and replace
  every claper.example.com", which is four places per file to get right.

  Deliberately public. The Microsoft 365 admin center fetches a manifest URL
  itself, unauthenticated, so a login here would break the one route that makes
  installing this a single paste. Nothing here is secret: the files name the
  public add-in pages and carry no token.

  The feature switch is applied for tidiness rather than as a boundary. It does
  not reach the add-in pages themselves: `/addin/sidebar.html` and
  `/addin/slide.html` are static files under `ClaperWeb.static_paths/0`, so
  `Plug.Static` answers them before the router is consulted, switch or no
  switch. What the switch does close is everything those pages need, the embed
  routes and the API, so an add-in installed against a server with it off loads
  and then cannot do anything.
  """

  use ClaperWeb, :controller

  @manifest_dir Path.join(__DIR__, "../../../priv/addin_manifests")

  @sidebar_path Path.expand(Path.join(@manifest_dir, "claper-sidebar.xml"))
  @slide_path Path.expand(Path.join(@manifest_dir, "claper-on-a-slide.xml"))

  # Read at compile time so a release carries them, and rebuilt when they change.
  @external_resource @sidebar_path
  @external_resource @slide_path

  # The comments in the templates address whoever edits them in the repository:
  # they say to replace the placeholder by hand and point at a path inside the
  # source tree. Served as-is they would tell a stranger to replace an address
  # that is already correct, and the substitution below would rewrite the
  # instruction itself into nonsense. A manifest needs no comments, so they go.
  @strip_comments ~r/\s*<!--.*?-->/s

  @sidebar_manifest Regex.replace(@strip_comments, File.read!(@sidebar_path), "")
  @slide_manifest Regex.replace(@strip_comments, File.read!(@slide_path), "")

  @placeholder "https://claper.example.com"

  def show(conn, _params) do
    conn
    |> assign(:sidebar_manifest_url, absolute("/addin/manifest/sidebar.xml"))
    |> assign(:slide_manifest_url, absolute("/addin/manifest/slide.xml"))
    |> render("show.html")
  end

  def sidebar(conn, _params), do: send_manifest(conn, @sidebar_manifest, "claper-sidebar.xml")

  def slide(conn, _params), do: send_manifest(conn, @slide_manifest, "claper-on-a-slide.xml")

  defp send_manifest(conn, template, filename) do
    conn
    |> put_resp_content_type("application/xml")
    # Inline rather than an attachment: the admin center reads this URL itself,
    # and a browser still saves it when the link that led here asks it to.
    |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
    |> send_resp(200, personalise(template))
  end

  @doc """
  Puts this server's address into a manifest template.

  The three addresses that name a page are built through the endpoint, so a
  Claper published under a path prefix gets `/prefix/addin/sidebar.html` rather
  than a manifest pointing one directory too high. What is left over is the
  bare origin, which is what `AppDomains` wants, and it is replaced last so the
  longer forms are not eaten first.
  """
  def personalise(template) do
    template
    |> String.replace(@placeholder <> "/addin/sidebar.html", absolute("/addin/sidebar.html"))
    |> String.replace(@placeholder <> "/addin/slide.html", absolute("/addin/slide.html"))
    |> String.replace(@placeholder <> "/images/favicon.png", absolute("/images/favicon.png"))
    |> String.replace(@placeholder, ClaperWeb.Endpoint.url())
  end

  defp absolute(path), do: ClaperWeb.Endpoint.url() <> ClaperWeb.Endpoint.path(path)
end
