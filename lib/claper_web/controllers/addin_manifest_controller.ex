defmodule ClaperWeb.AddinManifestController do
  @moduledoc """
  Serves the PowerPoint add-in manifests with this server's address filled in,
  and the page that explains how to install them.

  The routes are public because the Microsoft 365 admin center fetches manifest
  URLs without credentials. The manifests carry no token.
  """

  use ClaperWeb, :controller

  @manifest_dir Path.join(__DIR__, "../../../priv/addin_manifests")

  @sidebar_path Path.expand(Path.join(@manifest_dir, "claper-sidebar.xml"))
  @slide_path Path.expand(Path.join(@manifest_dir, "claper-on-a-slide.xml"))

  @external_resource @sidebar_path
  @external_resource @slide_path

  # The XML comments are editing instructions for the placeholder, which would be
  # wrong once the address is filled in.
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

  @doc """
  Returns the translated strings for the static add-in pages, which cannot use
  gettext themselves.
  """
  def strings(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=300")
    |> json(ClaperWeb.AddinStrings.all())
  end

  def sidebar(conn, _params), do: send_manifest(conn, @sidebar_manifest, "claper-sidebar.xml")

  def slide(conn, _params), do: send_manifest(conn, @slide_manifest, "claper-on-a-slide.xml")

  defp send_manifest(conn, template, filename) do
    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
    |> send_resp(200, personalise(template))
  end

  @doc """
  Puts this server's address into a manifest template.

  Page URLs go through the endpoint so a path prefix is kept. The bare origin
  is replaced last, since it is a prefix of the page URLs.
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
