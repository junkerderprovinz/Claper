defmodule ClaperWeb.EventLive.Presenter do
  use ClaperWeb, :live_view

  alias ClaperWeb.Presence
  alias Claper.Embeds.Embed
  alias Claper.Polls.Poll
  alias Claper.Forms.Form
  alias Claper.Quizzes.Quiz
  alias Claper.Presentations
  alias Claper.Transcriptions

  # Embeddable entry point. `ClaperWeb.PresenterEmbedAuth` has already verified
  # the token and loaded the event, so there is nothing left to authorize here.
  @impl true
  def mount(
        params,
        _session,
        %{assigns: %{presenter_embed: true, embed_event: event}} = socket
      ) do
    socket
    # An embed placed on a foreign slide pins one interaction instead of
    # following the deck: the slide it sits on is what selects it, and the
    # presenter advances PowerPoint rather than Claper. Scoped to the event, so
    # an id from another event resolves to nothing.
    |> assign(:pinned_poll_id, pinned_id(params["poll"]))
    |> assign(:pinned_quiz_id, pinned_id(params["quiz"]))
    |> assign(:pinned_form_id, pinned_id(params["form"]))
    |> assign(:embed_style, embed_style(params))
    |> assign(:embed_show, embed_show(params))
    |> mount_event(event, true)
  end

  @impl true
  def mount(%{"code" => code} = params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    event =
      Claper.Events.get_event_with_code(code, [
        :user,
        presentation_file: [:polls, :presentation_state]
      ])

    if is_nil(event) || not leader?(socket, event) do
      {:ok,
       socket
       |> put_flash(:error, gettext("Event doesn't exist"))
       |> redirect(to: "/")}
    else
      mount_event(socket, event, !is_nil(params["iframe"]))
    end
  end

  @doc """
  How an embedded interaction is drawn, from the query of the link.

  A block sitting on someone else's slide has to match that slide rather than
  Claper, so the look is part of the link instead of a fixed choice here:
  `theme` picks the readable default text colour, `panel` whether it brings a
  ground at all, `radius` how round the bars are and `shadow` whether it lifts
  off the page. `text` and `bar` override the two colours outright, for a deck
  whose own palette is neither of the two themes. Every value falls back to the
  readable default, so a hand-edited link cannot produce an invisible block.

  `panel` defaults to off. A block sits on a slide that already has a
  background, and a white card on top of it is a rectangle the author then has
  to design around. Asking for a ground is the deliberate choice, not being
  given one.

  `bg` is the colour of the page itself, and it exists because of a limit that
  is not Claper's. A web object on a PowerPoint slide cannot be see-through:
  Office paints an opaque ground under it whatever the page says, and the
  request to change that was closed as not planned. So a transparent page comes
  out white on the slide, and the only way to make the edge vanish is to paint
  the slide's own colour. Absent, the page stays transparent, which is right
  everywhere the host is not PowerPoint.
  """
  def embed_style(params) do
    %{
      theme: one_of(params["theme"], ~w(light dark), "light"),
      panel: one_of(params["panel"], ~w(on off), "off"),
      bg: colour(params["bg"]),
      radius: one_of(params["radius"], ~w(sharp soft round), "soft"),
      shadow: one_of(params["shadow"], ~w(on off), "off"),
      text: colour(params["text"]),
      bar: colour(params["bar"]),
      qr: qr_size(params["qr"]),
      # How the answers to an open question are drawn. A cloud by default,
      # because that is what an open question is asked for: one glance at what
      # the room agrees on. A list when the answers are sentences.
      layout: one_of(params["layout"], ~w(cloud list), "cloud"),
      # Whether a quiz block shows who is winning under the bars. Off by
      # default: a board is a thing an author decides to put on a slide, not
      # something that appears under every quiz they place.
      board: one_of(params["board"], ~w(on off), "off"),
      # What stands at the end of a bar. Both by default, which is what it has
      # always shown; the choice exists because the right answer depends on the
      # room and not on us.
      counts: one_of(params["counts"], ~w(both percent count), "both")
    }
  end

  @doc """
  The number at the end of a bar, in the form the author asked for.

  Both by default. A share on its own hides how few people it is drawn from -
  "67%" out of three votes reads like a finding - and a count on its own hides
  how large a share it is. Either alone is the right choice in some rooms, which
  is why it is a choice rather than a rule.
  """
  def poll_tally(percentage, _count, "percent"), do: "#{percentage}%"
  def poll_tally(_percentage, count, "count"), do: "#{count}"
  def poll_tally(percentage, count, _both), do: "#{percentage}% (#{count})"

  @doc """
  What the page paints behind everything.

  Black for the presenter's own full-screen deck, which is what a projected
  slide wants. For an embedded block it is transparent unless the link names a
  colour, and it names one when the block sits on a PowerPoint slide, where
  transparent is not a thing the host can honour.
  """
  def embed_background(false, _style), do: "black"
  def embed_background(true, %{bg: bg}) when is_binary(bg), do: bg
  def embed_background(true, _style), do: "transparent"

  @doc """
  The CSS a chosen text or bar colour needs, or nothing when neither was chosen.

  Written as a rule rather than an inline style on each element because the
  colours are spread over a dozen places in the template, and a rule states the
  intent once. `!important` is deliberate: the author picked a colour for this
  block, so it outranks the theme default it is replacing.

  The class is only on what carries the wording and on the filled part of a
  bar, which leaves the quiz's own right-and-wrong colouring alone.
  """
  def embed_css(%{text: nil, bar: nil}), do: nil

  def embed_css(style) do
    [
      if(style.text, do: ".claper-ink { color: #{style.text} !important; }"),
      if(style.bar, do: ".claper-bar { background-color: #{style.bar} !important; }")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  # Six hex digits, nothing else. The value comes out of a URL held by a
  # document Claper does not own, and it is written into a stylesheet, so
  # anything that is not exactly a colour is no colour at all.
  defp colour(value) when is_binary(value) do
    trimmed = String.trim_leading(value, "#")
    if trimmed =~ ~r/^[0-9a-fA-F]{6}$/, do: "#" <> String.downcase(trimmed), else: nil
  end

  defp colour(_), do: nil

  # How many pixels wide the joining code is drawn. The block on a slide wants
  # the small one it has always had; the sidebar asks for a large one because it
  # reads the drawing out and puts it on a slide as a picture, where 180 pixels
  # blown up to slide size is the blur that made it worth asking for.
  @qr_default 180
  @qr_max 1200

  defp qr_size(value) when is_binary(value) do
    case Integer.parse(value) do
      {size, ""} when size >= 120 and size <= @qr_max -> size
      _ -> @qr_default
    end
  end

  defp qr_size(_), do: @qr_default

  @doc """
  What an embedded block shows: the current interaction, the joining details or
  the audience's messages.

  `join` is the one that deliberately carries the event code, because a slide
  deck that keeps its own slides never shows Claper's joining screen, and
  without it nobody in the room can answer anything. Everywhere else the code
  stays out of the markup, so putting it on a slide has to be an explicit
  choice rather than a side effect.
  """
  def embed_show(params), do: one_of(params["show"], ~w(interaction join messages), "interaction")

  @doc """
  The messages an embedded block may show.

  Empty while the owner keeps the chat hidden, so hiding it on the projected
  view hides it on the slide too. Deleted posts stay in the list as tombstones
  for the live update on the presenter screen, and are dropped here.
  """
  def embed_posts(state, posts, pinned_posts)

  def embed_posts(%{chat_visible: false}, _posts, _pinned_posts), do: []

  def embed_posts(%{show_only_pinned: true}, _posts, pinned_posts),
    do: Enum.reject(pinned_posts, &(&1.__meta__.state == :deleted))

  def embed_posts(_state, posts, _pinned_posts),
    do: Enum.reject(posts, &(&1.__meta__.state == :deleted))

  @doc """
  The heading of an embedded quiz: its title while the questions are not being
  stepped through, and the current question once they are.
  """
  def quiz_heading(%Quiz{} = quiz, idx) when is_integer(idx) and idx >= 0 do
    case Enum.at(quiz.quiz_questions, idx) do
      nil -> quiz.title
      question -> question.content
    end
  end

  def quiz_heading(%Quiz{} = quiz, _idx), do: quiz.title

  @doc """
  The options of the question an embedded quiz is on, or none between questions.
  """
  def quiz_opts(%Quiz{} = quiz, idx) when is_integer(idx) and idx >= 0 do
    case Enum.at(quiz.quiz_questions, idx) do
      nil -> []
      question -> question.quiz_question_opts
    end
  end

  def quiz_opts(_quiz, _idx), do: []

  @doc """
  Colours one option of an embedded quiz.

  The correct one is marked only after the owner has released the results.
  Before that every option looks the same, because the embed sits on a slide the
  audience is looking at while it answers.
  """
  def quiz_opt_colours(opt, show_results, theme)

  def quiz_opt_colours(%{is_correct: true}, true, _theme), do: "bg-green-600 text-white"

  def quiz_opt_colours(_opt, _show_results, "dark"), do: "bg-white/15 text-white"

  def quiz_opt_colours(_opt, _show_results, _theme), do: "bg-gray-200 text-gray-900"

  @doc """
  The corner treatment a bar gets, from the link's `radius`.
  """
  def bar_radius("sharp"), do: "rounded-none"
  def bar_radius("round"), do: "rounded-3xl"
  def bar_radius(_soft), do: "rounded-md"

  defp one_of(value, allowed, fallback) when is_binary(value) do
    if value in allowed, do: value, else: fallback
  end

  defp one_of(_value, _allowed, fallback), do: fallback

  # The interaction id a pinned embed carries in its query, or nil. Anything
  # that is not a positive integer is nil rather than an error: the value comes
  # from a URL a third party document holds.
  defp pinned_id(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp pinned_id(_), do: nil

  defp mount_event(socket, event, iframe) do
    if connected?(socket) do
      Claper.Events.Event.subscribe(event.uuid)
      Claper.Presentations.subscribe(event.presentation_file.id)
    end

    endpoint_config = Application.get_env(:claper, ClaperWeb.Endpoint)[:url]
    port = endpoint_config[:port]
    scheme = endpoint_config[:scheme]
    host = endpoint_config[:host]
    path = endpoint_config[:path]

    default_ports = [80, 443]
    port_suffix = if port in default_ports, do: "", else: ":" <> Integer.to_string(port)

    host = "#{scheme}://#{host}#{port_suffix}/#{path}"

    transcription_config =
      Transcriptions.get_transcription_config(event.presentation_file.id)

    socket =
      socket
      |> assign(:attendees_nb, 1)
      |> assign(
        :host,
        host
      )
      |> assign(:event, event)
      |> assign(:iframe, iframe)
      # The interaction route drops the deck and the black ground, so the block
      # can sit on a slide of the document that embeds it.
      |> assign_new(:interaction_only, fn ->
        socket.assigns[:live_action] == :interaction
      end)
      |> assign_new(:pinned_poll_id, fn -> nil end)
      |> assign_new(:pinned_quiz_id, fn -> nil end)
      |> assign_new(:pinned_form_id, fn -> nil end)
      # No timer until the presenter moves to a question, which is what starts
      # one. A block that loaded first simply shows no clock.
      |> assign_new(:question_started_at, fn -> nil end)
      |> assign_new(:embed_style, fn -> embed_style(%{}) end)
      |> assign_new(:embed_show, fn -> "interaction" end)
      # False on the regular presenter route. The template uses it to leave the
      # join screen out entirely rather than only hiding it, because the join
      # screen carries the event code and the embeddable link is meant to be
      # read only.
      |> assign_new(:presenter_embed, fn -> false end)
      |> assign(:state, event.presentation_file.presentation_state)
      |> assign(:posts, list_posts(socket, event.uuid))
      |> assign(:pinned_posts, list_pinned_posts(socket, event.uuid))
      |> assign(:show_only_pinned, event.presentation_file.presentation_state.show_only_pinned)
      |> assign(:reacts, [])
      |> assign(:transcription_text, "")
      |> assign(:transcription_config, transcription_config)
      |> poll_at_position
      |> form_at_position
      |> embed_at_position
      |> quiz_at_position

    {:ok, socket, temporary_assigns: []}
  end

  defp update_post_in_list(posts, updated_post) do
    Enum.map(posts, fn post ->
      if post.id == updated_post.id, do: updated_post, else: post
    end)
  end

  defp leader?(%{assigns: %{current_user: current_user}} = _socket, event) do
    Claper.Events.led_by?(current_user.email, event) || event.user.id == current_user.id
  end

  defp leader?(_socket, _event), do: false

  @impl true
  def handle_info(%{event: "presence_diff"}, %{assigns: %{event: event}} = socket) do
    attendees = Presence.list("event:#{event.uuid}")
    {:noreply, push_event(socket, "update-attendees", %{count: Enum.count(attendees)})}
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    {:noreply,
     socket
     |> update(:posts, fn posts -> posts ++ [post] end)}
  end

  @impl true
  def handle_info({:post_pinned, post}, socket) do
    {:noreply,
     socket
     |> update(:pinned_posts, fn pinned_posts -> pinned_posts ++ [post] end)}
  end

  @impl true
  def handle_info({:post_unpinned, post}, socket) do
    {:noreply,
     socket
     |> update(:pinned_posts, fn pinned_posts ->
       Enum.reject(pinned_posts, fn p -> p.id == post.id end)
     end)}
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    {:noreply,
     socket
     |> assign(:state, state)
     |> push_event("page", %{current_page: state.position})
     |> push_event("reset-global-react", %{})
     |> poll_at_position
     |> embed_at_position}
  end

  @impl true
  def handle_info({:post_updated, updated_post}, socket) do
    updated_posts = update_post_in_list(socket.assigns.posts, updated_post)
    updated_pinned_posts = update_post_in_list(socket.assigns.pinned_posts, updated_post)

    {:noreply,
     socket
     |> assign(:posts, updated_posts)
     |> assign(:pinned_posts, updated_pinned_posts)}
  end

  @impl true
  def handle_info({:post_deleted, post}, socket) do
    updated_posts = Enum.reject(socket.assigns.posts, fn p -> p.id == post.id end)
    updated_pinned_posts = Enum.reject(socket.assigns.pinned_posts, fn p -> p.id == post.id end)

    {:noreply,
     socket |> assign(:posts, updated_posts) |> assign(:pinned_posts, updated_pinned_posts)}
  end

  @impl true
  def handle_info({:poll_updated, poll}, socket) do
    if poll.enabled do
      {:noreply,
       socket
       |> assign_poll(poll)}
    else
      {:noreply,
       socket
       |> assign_poll(nil)}
    end
  end

  @impl true
  def handle_info({:poll_deleted, _poll}, socket) do
    {:noreply,
     socket
     |> assign_poll(nil)}
  end

  # A block pinned to one form is not following the event, so a change to a
  # different form must not pull it off the one its slide names. Both of these
  # come before the general clauses on purpose.
  @impl true
  def handle_info({:form_updated, form}, %{assigns: %{pinned_form_id: id}} = socket)
      when is_integer(id) do
    if form.id == id and form.enabled do
      {:noreply, assign_form(socket, form)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:form_deleted, form}, %{assigns: %{pinned_form_id: id}} = socket)
      when is_integer(id) do
    if form.id == id do
      {:noreply, assign_form(socket, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:form_updated, form}, socket) do
    if form.enabled do
      {:noreply,
       socket
       |> assign_form(form)}
    else
      {:noreply,
       socket
       |> assign_form(nil)}
    end
  end

  @impl true
  def handle_info({:form_deleted, _form}, socket) do
    {:noreply,
     socket
     |> assign_form(nil)}
  end

  # Somebody in the room wrote something. Only reloaded when the form being
  # shown is the one that was written into, so a busy event does not re-query on
  # every submission to a form nobody is looking at.
  @impl true
  def handle_info(
        {event, submit},
        %{assigns: %{current_form: %Claper.Forms.Form{} = form}} = socket
      )
      when event in [:form_submit_created, :form_submit_updated, :form_submit_deleted] do
    if submit.form_id == form.id do
      {:noreply, assign_form(socket, form)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:embed_updated, embed}, socket) do
    if embed.enabled do
      {:noreply,
       socket
       |> update(:current_embed, fn _current_embed -> embed end)}
    else
      {:noreply,
       socket
       |> update(:current_embed, fn _current_embed -> nil end)}
    end
  end

  @impl true
  def handle_info({:embed_deleted, _embed}, socket) do
    {:noreply,
     socket
     |> update(:current_embed, fn _current_embed -> nil end)}
  end

  @impl true
  def handle_info({:quiz_updated, quiz}, socket) do
    {:noreply,
     socket
     |> assign_quiz(quiz)}
  end

  @impl true
  def handle_info({:quiz_deleted, _quiz}, socket) do
    {:noreply,
     socket
     |> assign_quiz(nil)}
  end

  @impl true
  def handle_info({:chat_visible, value}, socket) do
    {:noreply,
     socket
     |> push_event("chat-visible", %{value: value})
     |> update(:chat_visible, fn _chat_visible -> value end)}
  end

  @impl true
  def handle_info({:show_only_pinned, value}, socket) do
    {:noreply,
     socket
     |> push_event("show_only_pinned", %{value: value})
     |> update(:show_only_pinned, fn _show_only_pinned -> value end)}
  end

  @impl true
  def handle_info({:poll_visible, value}, socket) do
    {:noreply,
     socket
     |> push_event("poll-visible", %{value: value})
     |> update(:poll_visible, fn _poll_visible -> value end)}
  end

  @impl true
  def handle_info({:join_screen_visible, value}, socket) do
    {:noreply,
     socket
     |> push_event("join-screen-visible", %{value: value})
     |> update(:join_screen_visible, fn _join_screen_visible -> value end)}
  end

  @impl true
  def handle_info({:react, type}, socket) do
    {:noreply,
     socket
     |> push_event("global-react", %{type: type})}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Poll{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign_poll(interaction)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign_quiz(nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Embed{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_embed, interaction)
     |> assign_poll(nil)
     |> assign(:current_form, nil)
     |> assign_quiz(nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Form{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_form, interaction)
     |> assign_poll(nil)
     |> assign(:current_embed, nil)
     |> assign_quiz(nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Quiz{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign_quiz(interaction)
     |> assign_poll(nil)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, nil},
        socket
      ) do
    {:noreply,
     socket
     |> assign_poll(nil)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign_quiz(nil)}
  end

  @impl true
  def handle_info(
        {:review_quiz_questions},
        socket
      ) do
    move_to_quiz_question(socket, 0)
  end

  @impl true
  def handle_info(
        {:next_quiz_question},
        %{assigns: %{current_quiz: %Quiz{} = quiz, current_question_idx: idx}} = socket
      ) do
    next = if idx < length(quiz.quiz_questions) - 1, do: idx + 1, else: -1
    move_to_quiz_question(socket, next)
  end

  @impl true
  def handle_info({:next_quiz_question}, socket), do: {:noreply, socket}

  @impl true
  def handle_info(
        {:prev_quiz_question},
        %{assigns: %{current_quiz: %Quiz{}, current_question_idx: idx}} = socket
      ) do
    move_to_quiz_question(socket, max(idx - 1, 0))
  end

  @impl true
  def handle_info({:prev_quiz_question}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:transcription_created, transcription}, socket) do
    {:noreply, socket |> assign(:transcription_text, transcription.text)}
  end

  @impl true
  def handle_info({:transcription_delta, text}, socket) do
    {:noreply, socket |> assign(:transcription_text, text)}
  end

  @impl true
  def handle_info({:transcription_config_updated, config}, socket) do
    {:noreply, socket |> assign(:transcription_config, config)}
  end

  @impl true
  def handle_info({:transcription_config_deleted, _config}, socket) do
    {:noreply, socket |> assign(:transcription_config, nil)}
  end

  # Revoking a link, and ending the event, both have to reach the frames that
  # are already open, not just the next visitor. Navigating to a path the token
  # check cannot accept lets `ClaperWeb.Plugs.PresenterEmbedToken` answer with
  # its 404, and that response carries the frame headers, so the frame shows it
  # instead of going blank.
  #
  # A constant is used rather than the link that was just invalidated: the raw
  # token would otherwise have to sit in the assigns of a view anyone holding
  # the link can reach, where a crash report writes it to the log in clear
  # text. Any value that is not 32 base64 encoded bytes is rejected, so this one
  # can never name a real link.
  #
  # Both clauses sit before the catch-all below, which would otherwise swallow
  # the messages.
  @ended_embed_path "/embed/presenter/ended"

  @impl true
  def handle_info({:presenter_embed_revoked}, %{assigns: %{presenter_embed: true}} = socket) do
    {:noreply, redirect(socket, to: @ended_embed_path)}
  end

  @impl true
  def handle_info({:event_terminated, _uuid}, %{assigns: %{presenter_embed: true}} = socket) do
    {:noreply, redirect(socket, to: @ended_embed_path)}
  end

  @impl true
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
  end

  defp apply_action(socket, :embed, _params) do
    socket
  end

  defp apply_action(socket, :interaction, _params) do
    socket
  end

  # An embed keeps the interaction its link names whatever the deck does, so the
  # presenter moving through Claper cannot change what a PowerPoint slide shows.
  defp poll_at_position(%{assigns: %{pinned_poll_id: id, event: event}} = socket)
       when is_integer(id) do
    assign_poll(socket, Claper.Polls.get_poll_for_event(id, event.id))
  end

  # A link that names a quiz named one interaction, not two, so the poll the
  # presenter happens to be standing on in Claper does not come along with it.
  defp poll_at_position(%{assigns: %{pinned_quiz_id: id}} = socket) when is_integer(id) do
    assign(socket, :current_poll, nil)
  end

  defp poll_at_position(%{assigns: %{pinned_form_id: id}} = socket) when is_integer(id) do
    assign(socket, :current_poll, nil)
  end

  defp poll_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with poll <-
           Claper.Polls.get_poll_current_position(
             event.presentation_file.id,
             state.position
           ) do
      assign_poll(socket, poll)
    end
  end

  # The pinned pair, same as polls and quizzes: a link that names a form shows
  # that form and nothing the presenter is standing on in Claper.
  defp form_at_position(%{assigns: %{pinned_form_id: id, event: event}} = socket)
       when is_integer(id) do
    form = Claper.Forms.get_form_for_event(id, event.id)
    assign_form(socket, form)
  end

  defp form_at_position(%{assigns: %{pinned_poll_id: id}} = socket) when is_integer(id) do
    assign_form(socket, nil)
  end

  defp form_at_position(%{assigns: %{pinned_quiz_id: id}} = socket) when is_integer(id) do
    assign_form(socket, nil)
  end

  defp form_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with form <-
           Claper.Forms.get_form_current_position(
             event.presentation_file.id,
             state.position
           ) do
      assign_form(socket, form)
    end
  end

  # The poll and, for a ranking, the order the room has put its options in.
  # Only read for a ranking: a poll and a scale carry their result in the option
  # counts already, and reading every vote for them would be a query per update
  # for a number that is right there.
  defp assign_poll(socket, poll) do
    # Three of the shapes are results the vote rows have to be read for; the
    # rest are answered by the counter on the option and need nothing. One
    # query serves whichever of the three this is, rather than one per shape.
    votes =
      if poll && poll.style in ~w(ranking points pins) do
        Claper.Polls.list_poll_votes(poll.id)
      else
        []
      end

    socket
    |> assign(:current_poll, poll)
    |> assign(
      :poll_ranked,
      if(poll && poll.style == "ranking", do: ranked(poll, votes), else: [])
    )
    |> assign(:poll_spent, if(poll && poll.style == "points", do: spent(poll, votes), else: []))
    |> assign(:poll_pins, if(poll && poll.style == "pins", do: pins(votes), else: []))
    |> assign(:wheel_opt, wheel_opt(socket, poll))
  end

  # Looked up in the poll rather than trusted from the state, which holds a
  # bare id: a poll edited since the spin may no longer have that option, and a
  # slide is not the place to find that out.
  defp wheel_opt(socket, %Claper.Polls.Poll{style: "wheel"} = poll) do
    case socket.assigns[:state] do
      %{wheel_opt_id: id} when is_integer(id) ->
        Enum.find(poll.poll_opts || [], &(&1.id == id))

      _ ->
        nil
    end
  end

  defp wheel_opt(_socket, _poll), do: nil

  defdelegate ranked(poll, votes), to: Claper.Polls.Poll
  defdelegate spent(poll, votes), to: Claper.Polls.Poll
  defdelegate pins(votes), to: Claper.Polls.Poll

  # The quiz and the board that goes under it. Only queried when a link asked
  # for the board: it reads every response of the quiz, and quiz_updated
  # arrives once per answer given in the room.
  defp assign_quiz(socket, quiz) do
    board =
      if quiz && socket.assigns[:embed_style][:board] == "on" do
        Claper.Quizzes.leaderboard(quiz.id)
      else
        []
      end

    socket |> assign(:current_quiz, quiz) |> assign(:quiz_board, board)
  end

  # The form and everything derived from it, in one place. The cloud is counted
  # here rather than in the template, which would recount it once per word.
  defp assign_form(socket, form) do
    answers = form_answers(form)

    socket
    |> assign(:current_form, form)
    |> assign(:form_answers, answers)
    |> assign(:form_cloud, form_cloud(answers))
  end

  @doc """
  What people have written into a form, newest first, as plain strings.

  A form is Claper's open question: several named fields, each answered in free
  text. On a slide the field names are already on the slide, so what is worth
  showing is the writing itself. One entry per filled field rather than one per
  person, because two people answering two questions is four things to read,
  not two.

  Blank fields are dropped rather than rendered as gaps, and the response map's
  own key order is not meaningful, so it is sorted to keep the list stable
  between updates.
  """
  def form_answers(nil), do: []

  def form_answers(%Claper.Forms.Form{} = form) do
    form.id
    |> Claper.Forms.list_form_submits_for_form()
    |> Enum.flat_map(fn submit ->
      submit.response
      |> Enum.sort_by(fn {name, _value} -> name end)
      |> Enum.map(fn {_name, value} -> to_string(value) |> String.trim() end)
      |> Enum.reject(&(&1 == ""))
    end)
  end

  @doc """
  The same answers counted, as `{text, count}` from most said to least.

  What makes a word cloud worth having over a list: when eleven people write
  "tired", the room should see one large "tired" rather than eleven identical
  lines. Counted case-insensitively because "Tired" and "tired" are the same
  answer, and shown in the spelling that was used most often, so a cloud of
  names is not flattened to lower case.

  Ties keep the order they arrived in, so the cloud does not reshuffle itself
  every time somebody answers.
  """
  def form_cloud(answers) when is_list(answers) do
    answers
    |> Enum.reduce({%{}, []}, fn answer, {seen, order} ->
      key = answer |> String.downcase() |> String.trim()
      # Kept in the order they arrived, not counted into a map: when two
      # spellings are equally common the choice between them still has to be
      # the same one every time, and a map has no order to fall back on.
      spellings = Map.get(seen, key, []) ++ [answer]

      {Map.put(seen, key, spellings), if(key in order, do: order, else: order ++ [key])}
    end)
    |> then(fn {seen, order} ->
      order
      |> Enum.map(fn key ->
        spellings = seen[key]
        counts = Enum.frequencies(spellings)
        most = counts |> Map.values() |> Enum.max()

        {Enum.find(spellings, &(counts[&1] == most)), length(spellings)}
      end)
      |> Enum.sort_by(fn {_text, count} -> -count end)
    end)
  end

  @doc """
  How big one word in the cloud is drawn, as a Tailwind class.

  Relative to the most said answer rather than to an absolute count, because a
  cloud of three answers and a cloud of three hundred both have to read as a
  cloud. A long answer is stepped down: twelve words set in the largest size is
  a paragraph shouting, not a word cloud.
  """
  def cloud_size(count, top) when is_integer(count) and is_integer(top) and top > 0 do
    case count / top do
      share when share > 0.75 -> "text-5xl font-bold"
      share when share > 0.5 -> "text-4xl font-bold"
      share when share > 0.3 -> "text-3xl font-semibold"
      share when share > 0.15 -> "text-2xl font-semibold"
      _ -> "text-xl"
    end
  end

  def cloud_size(_count, _top), do: "text-xl"

  @doc """
  The same, stepped down for an answer that is a sentence rather than a word.
  """
  def cloud_class(text, count, top) do
    size = cloud_size(count, top)

    if String.length(text) > 24 do
      size
      |> String.replace("text-5xl", "text-2xl")
      |> String.replace("text-4xl", "text-xl")
      |> String.replace("text-3xl", "text-lg")
      |> String.replace("text-2xl", "text-base")
    else
      size
    end
  end

  defp embed_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with embed <-
           Claper.Embeds.get_embed_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign(:current_embed, embed)
    end
  end

  # Stepping through the questions is broadcast to every viewer of the event,
  # but the component that holds the question index is not on every viewer's
  # screen: an embed only mounts it once results are released, and an embedded
  # interaction block draws the quiz itself. Updating a component that is not
  # there raises, so the index is kept in the socket and only handed on when the
  # component really is mounted.
  defp move_to_quiz_question(socket, idx) do
    if quiz_component_mounted?(socket) do
      send_update(
        ClaperWeb.EventLive.ManageableQuizComponent,
        id: "#{socket.assigns.current_quiz.id}-quiz",
        current_question_idx: idx
      )
    end

    # When the timer starts, for a quiz that has one. Stamped here rather than
    # when a block loads, because a block on a slide is loaded long before the
    # presenter reaches it: PowerPoint builds the add-ins on the slide ahead of
    # showing them. Moving to the question is the moment the room is asked.
    {:noreply,
     socket
     |> assign(:current_question_idx, idx)
     |> assign(:question_started_at, DateTime.utc_now() |> DateTime.to_unix())}
  end

  defp quiz_component_mounted?(%{assigns: %{current_quiz: %Quiz{} = quiz} = assigns}) do
    !assigns.interaction_only && (!assigns.presenter_embed || quiz.show_results)
  end

  defp quiz_component_mounted?(_socket), do: false

  defp quiz_at_position(%{assigns: %{pinned_quiz_id: id, event: event}} = socket)
       when is_integer(id) do
    quiz =
      Claper.Quizzes.get_quiz_for_event(id, event.id, [
        :quiz_questions,
        quiz_questions: :quiz_question_opts
      ])

    socket |> assign_quiz(quiz) |> assign(:current_question_idx, 0)
  end

  # The other half of the pair above: a link that names a poll shows that poll
  # alone.
  defp quiz_at_position(%{assigns: %{pinned_poll_id: id}} = socket) when is_integer(id) do
    socket |> assign_quiz(nil) |> assign(:current_question_idx, 0)
  end

  defp quiz_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with quiz <-
           Claper.Quizzes.get_quiz_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign_quiz(quiz) |> assign(:current_question_idx, 0)
    end
  end

  defp list_posts(_socket, event_id) do
    Claper.Posts.list_posts(event_id, [:event, :reactions])
  end

  defp list_pinned_posts(_socket, event_id) do
    Claper.Posts.list_pinned_posts(event_id, [:event, :reactions])
  end

  @doc """
  URL of the page currently projected, or nil when the deck has none.

  The embeddable view renders this one page instead of the whole deck, the same
  way an attendee's device does, so a page the presenter has not reached is not
  in the markup an audience can read.
  """
  def current_slide_url(presentation_file, position) do
    presentation_file
    |> Claper.Presentations.get_slide_urls()
    |> Enum.at(position)
  end
end
