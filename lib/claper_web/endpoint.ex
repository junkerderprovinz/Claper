defmodule ClaperWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :claper

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_claper_key",
    signing_salt: "Tg18Y2zU",
    # 30 days
    max_age: 24 * 60 * 60 * 30
  ]

  socket "/audio", ClaperWeb.AudioSocket,
    websocket: [timeout: 120_000],
    longpoll: false

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [
        session: {__MODULE__, :runtime_opts, []}
      ]
    ]

  # The add-in's two pages, ahead of the general static plug so this one answers
  # them.
  #
  # Everything else under priv/static carries a content hash in its name, so
  # "cache for as long as you like" is right for it. These two do not: their
  # addresses are fixed, because the manifest installed in Office points at
  # them by name and cannot be re-pointed without reinstalling the add-in.
  # Served with the default "public" and no expiry, Office was free to keep a
  # copy for as long as it liked - and did, which is why a fixed page kept
  # showing the old text on the machine it was fixed for. Measured on the live
  # instance: the file served was byte-identical to the repository while the
  # add-in in PowerPoint still showed text that file no longer contains.
  #
  # "no-cache" does not mean "do not store". It means "ask before using what
  # you stored", so the ETag still answers almost every request with a 304 and
  # nothing but the headers travels.
  plug Plug.Static,
    at: "/",
    from: :claper,
    gzip: false,
    only: ~w(addin),
    cache_control_for_etags: "no-cache"

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :claper,
    gzip: false,
    only: ClaperWeb.static_paths()

  plug Plug.Static,
    at: "/uploads",
    from: Path.join([Application.compile_env(:claper, :storage_dir), "uploads"]),
    gzip: false

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :claper
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  plug(:runtime_session)

  plug RemoteIp,
    proxies: {Application, :get_env, [:claper, :remote_ip_proxies, []]},
    headers: {Application, :get_env, [:claper, :remote_ip_headers, []]}

  plug ClaperWeb.Router

  def runtime_session(conn, _opts) do
    Plug.run(conn, [{Plug.Session, runtime_opts()}])
  end

  def runtime_opts() do
    @session_options
    |> Keyword.put(:same_site, Application.get_env(:claper, __MODULE__)[:same_site_cookie])
    |> Keyword.put(:secure, Application.get_env(:claper, __MODULE__)[:secure_cookie])
  end
end
