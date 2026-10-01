defmodule ClaperWeb.Router do
  use ClaperWeb, :router

  import ClaperWeb.{UserAuth, EventController}

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {ClaperWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
    plug(ClaperWeb.Plugs.Locale)
  end

  pipeline :admin_required do
    plug(ClaperWeb.Plugs.AdminRequiredPlug)
  end

  pipeline :lti do
    plug(:accepts, ["html", "json"])
    plug(:put_root_layout, html: {ClaperWeb.LayoutView, :root})
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:fetch_current_user)
    plug(ClaperWeb.Plugs.Locale)
  end

  pipeline :protect_mailbox do
    plug ClaperWeb.MailboxGuard
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :rate_limit_auth do
    plug ClaperWeb.Plugs.RateLimitPlug,
      max_requests: 10,
      interval_ms: 60_000,
      prefix: "auth"
  end

  # Manage attendee_identifier in requests
  pipeline :attendee_registration do
    plug(:attendee_identifier)
  end

  live_session :attendee do
    scope "/", ClaperWeb do
      pipe_through([:browser, :attendee_registration, ClaperWeb.Plugs.Iframe])

      live("/", EventLive.Join, :index)
      live("/join", EventLive.Join, :join)
      live("/e/:code", EventLive.Show, :show)
    end
  end

  live_session :user,
    root_layout: {ClaperWeb.LayoutView, :user} do
    scope "/", ClaperWeb do
      pipe_through([:browser, :require_authenticated_user])

      post "/export/forms/:form_id", StatController, :export_form
      post "/export/polls/:poll_id", StatController, :export_poll
      post "/export/quizzes/:quiz_id", StatController, :export_quiz
      post "/export/quizzes/:quiz_id/qti", StatController, :export_quiz_qti
      post "/export/:event_id/messages", StatController, :export_all_messages
      post "/export/:event_id/transcriptions", StatController, :export_transcriptions

      live("/events", EventLive.Index, :index)
      live("/events/new", EventLive.Index, :new)
      live("/events/:id/edit", EventLive.Index, :edit)
      live("/events/:id/stats", StatLive.Index, :index)

      live("/users/settings", UserSettingsLive.Show, :show)
      live("/users/settings/edit/profile", UserSettingsLive.Show, :edit_profile)
      live("/users/settings/edit/password", UserSettingsLive.Show, :edit_password)
      live("/users/settings/edit/email", UserSettingsLive.Show, :edit_email)
      live("/users/settings/set/password", UserSettingsLive.Show, :set_password)
    end
  end

  live_session :presenter, on_mount: ClaperWeb.UserLiveAuth do
    scope "/", ClaperWeb do
      pipe_through([:browser, :require_authenticated_user])

      live("/e/:code/presenter", EventLive.Presenter, :show)
      live("/e/:code/manage", EventLive.Manage, :show)
      live("/e/:code/manage/add/poll", EventLive.Manage, :add_poll)
      live("/e/:code/manage/edit/poll/:id", EventLive.Manage, :edit_poll)
      live("/e/:code/manage/add/form", EventLive.Manage, :add_form)
      live("/e/:code/manage/import", EventLive.Manage, :import)
      live("/e/:code/manage/edit/form/:id", EventLive.Manage, :edit_form)
      live("/e/:code/manage/add/embed", EventLive.Manage, :add_embed)
      live("/e/:code/manage/edit/embed/:id", EventLive.Manage, :edit_embed)
      live("/e/:code/manage/add/quiz", EventLive.Manage, :add_quiz)
      live("/e/:code/manage/edit/quiz/:id", EventLive.Manage, :edit_quiz)
      live("/e/:code/manage/add/transcription", EventLive.Manage, :add_transcription)
      live("/e/:code/manage/edit/transcription/:id", EventLive.Manage, :edit_transcription)
    end
  end

  # Read-only presenter views for framing in other documents, authorized by a
  # revocable token. The event code stays out of the path, since it lets anyone join.
  live_session :presenter_embed, on_mount: ClaperWeb.PresenterEmbedAuth do
    scope "/", ClaperWeb do
      # The frame plug runs first so the token plug's 404 can still show in the frame.
      pipe_through([
        :browser,
        ClaperWeb.Plugs.PresenterEmbedFrame,
        ClaperWeb.Plugs.PresenterEmbedToken
      ])

      live("/embed/presenter/:token", EventLive.Presenter, :embed)

      # The interaction alone, without the deck, for a block placed on a slide.
      live("/embed/interaction/:token", EventLive.Presenter, :interaction)
    end
  end

  # PowerPoint sidebar API. These routes need no event yet, since they are how
  # the sidebar finds one.
  scope "/api/addin", ClaperWeb do
    pipe_through([:api, ClaperWeb.Plugs.PresenterEmbedEnabled, ClaperWeb.Plugs.AddinToken])

    get("/me", AddinController, :me)
    get("/events", AddinController, :event_index)
    post("/events", AddinController, :event_create)
  end

  # Routes for one event, which AddinEvent resolves from the key or the request.
  scope "/api/addin", ClaperWeb do
    pipe_through([
      :api,
      ClaperWeb.Plugs.PresenterEmbedEnabled,
      ClaperWeb.Plugs.AddinToken,
      ClaperWeb.Plugs.AddinEvent
    ])

    get("/polls", AddinController, :index)
    post("/polls", AddinController, :create)
    patch("/polls/:id", AddinController, :update)
    delete("/polls/:id", AddinController, :delete)

    get("/quizzes", AddinController, :quiz_index)
    post("/quizzes", AddinController, :quiz_create)
    patch("/quizzes/:id", AddinController, :quiz_update)
    delete("/quizzes/:id", AddinController, :quiz_delete)

    get("/forms", AddinController, :form_index)
    post("/forms", AddinController, :form_create)
    patch("/forms/:id", AddinController, :form_update)
    delete("/forms/:id", AddinController, :form_delete)

    post("/embed_token", AddinController, :embed_token)
    post("/slide", AddinController, :slide)
  end

  # Add-in manifests are public so the Microsoft 365 admin center can fetch them
  # by URL. Phoenix picks the format from the Accept header, and `:browser` would
  # answer an XML request with 406. A file under priv/static/addin/manifest/
  # would be served by Plug.Static instead of these routes.
  pipeline :addin_manifest do
    plug(:accepts, ["xml", "html"])
    plug(:put_secure_browser_headers)
  end

  scope "/addin", ClaperWeb do
    pipe_through([:addin_manifest, ClaperWeb.Plugs.PresenterEmbedEnabled])

    get("/manifest/sidebar.xml", AddinManifestController, :sidebar)
    get("/manifest/slide.xml", AddinManifestController, :slide)
  end

  # Translations for the static add-in pages, which cannot use gettext themselves.
  scope "/addin", ClaperWeb do
    pipe_through([:api, ClaperWeb.Plugs.PresenterEmbedEnabled])

    get("/strings.json", AddinManifestController, :strings)
  end

  # Add-in install page.
  scope "/addin", ClaperWeb do
    pipe_through([:browser, ClaperWeb.Plugs.PresenterEmbedEnabled])

    get("/", AddinManifestController, :show)
  end

  # Interactions a slide block can offer, reached with the read-only embed token.
  scope "/api/embed", ClaperWeb do
    pipe_through([:api, ClaperWeb.Plugs.PresenterEmbedEnabled, ClaperWeb.Plugs.EmbedCatalogToken])

    get("/:token/interactions", EmbedCatalogController, :index)
  end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through(:browser)
      live_dashboard("/dashboard", metrics: ClaperWeb.Telemetry)
    end
  end

  # Enables the Swoosh mailbox preview in development.
  #
  # Note that preview only shows emails that were sent by the same
  # node running the Phoenix server.
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through [:browser, :protect_mailbox]
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  ## Authentication routes
  scope "/", ClaperWeb do
    pipe_through([:browser, :redirect_if_user_is_authenticated, :rate_limit_auth])

    get("/users/register", UserRegistrationController, :new)
    post("/users/register", UserRegistrationController, :create)

    get("/users/register/confirm", UserRegistrationController, :confirm)
    get("/users/log_in", UserSessionController, :new)
    post("/users/log_in", UserSessionController, :create)
    get("/users/magic/:token", UserConfirmationController, :confirm_magic)
    get("/users/reset_password", UserResetPasswordController, :new)
    post("/users/reset_password", UserResetPasswordController, :create)
    get("/users/reset_password/:token", UserResetPasswordController, :edit)
    post("/users/reset_password/:token", UserResetPasswordController, :update)

    get("/users/confirm", UserConfirmationController, :new)
    post("/users/confirm", UserConfirmationController, :create)
    get("/users/confirm/:token", UserConfirmationController, :update)

    get("/users/oidc", UserOidcAuth, :new)
    get("/users/oidc/callback", UserOidcAuth, :callback)
  end

  scope "/", ClaperWeb do
    pipe_through([:lti])

    get("/.well-known/jwks.json", Lti.RegistrationController, :jwks)
    get("/lti/register", Lti.RegistrationController, :new)
    post("/lti/register", Lti.RegistrationController, :create)
    post("/lti/login", Lti.LaunchController, :login)
    get("/lti/login", Lti.LaunchController, :login)
    post("/lti/launch", Lti.LaunchController, :launch)
  end

  scope "/", ClaperWeb do
    pipe_through([:browser, :require_authenticated_user])

    post("/events/:uuid/slide.jpg", EventController, :slide_generate)
    get("/users/settings/confirm_email/:token", UserSettingsController, :confirm_email)
    delete("/users/register/delete", UserRegistrationController, :delete)
  end

  scope "/", ClaperWeb do
    pipe_through([:browser])

    get("/tos", PageController, :tos)
    get("/privacy", PageController, :privacy)

    delete("/users/log_out", UserSessionController, :delete)
  end

  # Admin panel routes - LiveView implementation
  live_session :admin, root_layout: {ClaperWeb.LayoutView, :admin} do
    scope "/admin", ClaperWeb.AdminLive do
      pipe_through [:browser, :require_authenticated_user, :admin_required]

      live "/", DashboardLive, :index

      live "/users", UserLive, :index
      live "/users/new", UserLive, :new
      live "/users/:id/edit", UserLive, :edit
      live "/users/:id", UserLive, :show

      live "/events", EventLive, :index
      live "/events/new", EventLive, :new
      live "/events/:id/edit", EventLive, :edit
      live "/events/:id", EventLive, :show

      live "/oidc_providers", OidcProviderLive, :index
      live "/oidc_providers/new", OidcProviderLive, :new
      live "/oidc_providers/:id/edit", OidcProviderLive, :edit
      live "/oidc_providers/:id", OidcProviderLive, :show

      live "/audit_logs", AuditLogLive, :index
      live "/audit_logs/:id", AuditLogLive, :show

      live "/settings", SettingsLive, :index
    end
  end
end
