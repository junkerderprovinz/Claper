defmodule ClaperWeb.AddinManifestView do
  use ClaperWeb, :view

  @doc """
  The Alpine handler behind a "Copy link" button.

  Two things it has to survive. `navigator.clipboard` is undefined outside a
  secure context, and a self-hosted Claper reached over plain http or a bare LAN
  address is exactly that, so an unguarded call throws and the button does
  nothing with no explanation. And the address is spliced into a JavaScript
  string literal, where HTML escaping does not help: the browser decodes an
  escaped quote back to a quote before Alpine ever reads the attribute. So the
  quotes are escaped for JavaScript here.
  """
  def copy_script(url) do
    escaped = url |> String.replace("\\", "\\\\") |> String.replace("'", "\\'")

    "navigator.clipboard && navigator.clipboard.writeText('#{escaped}')" <>
      ".then(() => { copied = true; setTimeout(() => copied = false, 1500) })"
  end
end
