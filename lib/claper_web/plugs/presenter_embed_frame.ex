defmodule ClaperWeb.Plugs.PresenterEmbedFrame do
  @moduledoc """
  Allows a single route to be framed by the origins an operator opted in to.

  `put_secure_browser_headers/2` sets `x-frame-options: SAMEORIGIN` on every
  browser response. This plug replaces that header with a
  `content-security-policy: frame-ancestors` allow list, on the responses it is
  mounted on and nowhere else. The `:browser` pipeline stays untouched, so no
  other part of the application becomes embeddable.

  `frame-ancestors` is used rather than `x-frame-options: ALLOWALL` because
  `ALLOWALL` is not a value the specification defines and cannot express an
  allow list. The default is `'none'`, so an upgrade alone changes nothing:
  framing only becomes possible once `PRESENTER_EMBED_FRAME_ANCESTORS` is set.

  ## Configuration

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
  The `frame-ancestors` value this plug would send, after sanitising.

  The management screen uses it to tell an operator whether framing is actually
  switched on, so the answer comes from the same code that writes the header
  rather than from a second, slightly different check.
  """
  def frame_ancestors do
    Application.get_env(:claper, :presenter_embed_frame_ancestors, @default_ancestors)
    |> sanitize()
  end

  @doc """
  True when at least one origin may frame the embeddable view.
  """
  def framing_allowed?, do: frame_ancestors() != @default_ancestors

  # The value reaches a response header, so sources are allow listed rather
  # than escaped: a stray semicolon would otherwise append a second CSP
  # directive, and a newline would split the header.
  #
  # A malformed value falls back to `'none'` as a whole rather than being
  # filtered source by source. Filtering keeps whatever happens to look like a
  # source, and the leftovers of a broken value can be more permissive than
  # anything the operator wrote: `"https://example.com; default-src *"` loses
  # the semicolon-terminated origin and keeps `default-src *`, which allows
  # every origin to frame the page. Failing the whole value closed cannot
  # widen access by accident.
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

  # A source has to name a host. `*`, `https://*`, `https:` and `//evil.com` are
  # all valid CSP and all mean "anyone", which is never what an allow list is
  # for, and `x-frame-options` has already been deleted by the time this value
  # is written. A subdomain wildcard such as `https://*.office.com` is fine
  # because what follows the wildcard is still a host.
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

  # At least one real character, and a leading wildcard has to be followed by a
  # dot, so `*.office.com` names something while `*` and `*:443` do not.
  defp named_host?(host) do
    String.match?(host, ~r{[A-Za-z0-9]}) and
      (not String.starts_with?(host, "*") or String.starts_with?(host, "*."))
  end
end
