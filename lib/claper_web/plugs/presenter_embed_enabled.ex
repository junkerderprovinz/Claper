defmodule ClaperWeb.Plugs.PresenterEmbedEnabled do
  @moduledoc """
  Refuses everything when the presenter embed feature is switched off.

  The switch is the same one the embed routes use, so a server that never opted
  in has neither the views nor the API. It asks
  `ClaperWeb.Plugs.PresenterEmbedFrame` rather than reading the setting again,
  because a value that plug rejects as a whole must count as off here too.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if ClaperWeb.Plugs.PresenterEmbedFrame.framing_allowed?() do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, ~s({"error":"not found"}))
      |> halt()
    end
  end
end
