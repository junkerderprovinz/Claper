defmodule ClaperWeb.Plugs.PresenterEmbedFrame do
  @moduledoc """
  Replaces `x-frame-options` with a `frame-ancestors` allow list on the routes it
  is mounted on, so only those can be framed, and only by the configured origins.
  The default is `'none'`.

      config :claper, presenter_embed_frame_ancestors: "https://*.officeapps.live.com"
  """

  import Plug.Conn

  @default_ancestors "'none'"
  @allowed_keywords ~w('none' 'self')

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> delete_resp_header("x-frame-options")
    |> put_resp_header("content-security-policy", "frame-ancestors #{frame_ancestors()}")
  end

  @doc """
  Returns the sanitised `frame-ancestors` value this plug sends.
  """
  def frame_ancestors do
    case Application.get_env(:claper, :presenter_embed_frame_ancestors, @default_ancestors)
         |> sanitize() do
      @default_ancestors ->
        @default_ancestors

      allowed ->
        # The add-in page is served from this origin and frames the interaction view.
        "'self' " <> allowed
    end
  end

  @doc """
  True when at least one origin may frame the embeddable view.
  """
  def framing_allowed?, do: frame_ancestors() != @default_ancestors

  # The value goes into a response header, where a semicolon would start another
  # CSP directive. A malformed value falls back to `'none'` as a whole, because
  # dropping only the bad sources can leave something wider than what was written.
  defp sanitize(value) when is_binary(value) do
    sources = String.split(value, ~r/[\s,]+/, trim: true)

    if sources != [] and Enum.all?(sources, &valid_source?/1) do
      Enum.join(sources, " ")
    else
      @default_ancestors
    end
  end

  defp sanitize(_value), do: @default_ancestors

  defp valid_source?(source) when source in @allowed_keywords, do: true

  # `*`, `https://*` and `https:` are valid CSP but let any origin frame the page,
  # so a source has to name a host. `https://*.office.com` still does.
  defp valid_source?(source) do
    String.match?(source, ~r{\A[A-Za-z0-9\.\-\*:/\[\]]+\z}) and
      not String.ends_with?(source, ":") and
      not String.starts_with?(source, "//") and
      source |> host_part() |> named_host?()
  end

  defp host_part(source) do
    case String.split(source, "://", parts: 2) do
      [_scheme, host] -> host
      [host] -> host
    end
  end

  # `*.office.com` names a host, `*` and `*:443` do not.
  defp named_host?(host) do
    String.match?(host, ~r{[A-Za-z0-9]}) and
      (not String.starts_with?(host, "*") or String.starts_with?(host, "*."))
  end
end
