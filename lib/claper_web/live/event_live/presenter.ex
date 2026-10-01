defmodule ClaperWeb.EventLive.Presenter do
  use ClaperWeb, :live_view

  alias ClaperWeb.Presence
  alias Claper.Embeds.Embed
  alias Claper.Polls.Poll
  alias Claper.Forms.Form
  alias Claper.Quizzes.Quiz
  alias Claper.Presentations
  alias Claper.Transcriptions

  # `ClaperWeb.PresenterEmbedAuth` has already verified the token and loaded the event.
  @impl true
  def mount(
        params,
        _session,
        %{assigns: %{presenter_embed: true, embed_event: event}} = socket
      ) do
    socket
    # The slide in PowerPoint picks the interaction, not the position in Claper.
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
  Reads the look of an embedded block from the link's query, falling back to the
  default for anything missing or invalid.

  `bg` paints the page itself, because PowerPoint draws an opaque ground under a
  web object and a transparent page would show up white on the slide.
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
      counts: one_of(params["counts"], ~w(both percent count), "both")
    }
  end

  @doc """
  Formats the number at the end of a bar as a percentage, a count or both.
  """
  def poll_tally(percentage, _count, "percent"), do: "#{percentage}%"
  def poll_tally(_percentage, count, "count"), do: "#{count}"
  def poll_tally(percentage, count, _both), do: "#{percentage}% (#{count})"

  @doc """
  Page background: black for the deck, otherwise the link's `bg` or transparent.
  """
  def embed_background(false, _style), do: "black"
  def embed_background(true, %{bg: bg}) when is_binary(bg), do: bg
  def embed_background(true, _style), do: "transparent"

  @doc """
  CSS for the text and bar colours chosen in the link, or nil when neither was.
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

  # The value is written into a stylesheet, so only six hex digits pass.
  defp colour(value) when is_binary(value) do
    trimmed = String.trim_leading(value, "#")
    if trimmed =~ ~r/^[0-9a-fA-F]{6}$/, do: "#" <> String.downcase(trimmed), else: nil
  end

  defp colour(_), do: nil

  # The sidebar asks for a large QR code when it places it on a slide as a picture.
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
  Which block an embed shows: the interaction, the joining details or the
  messages. Only `join` puts the event code into the markup.
  """
  def embed_show(params), do: one_of(params["show"], ~w(interaction join messages), "interaction")

  @doc """
  Messages for an embedded block: none while the chat is hidden, never deleted ones.
  """
  def embed_posts(state, posts, pinned_posts)

  def embed_posts(%{chat_visible: false}, _posts, _pinned_posts), do: []

  def embed_posts(%{show_only_pinned: true}, _posts, pinned_posts),
    do: Enum.reject(pinned_posts, &(&1.__meta__.state == :deleted))

  def embed_posts(_state, posts, _pinned_posts),
    do: Enum.reject(posts, &(&1.__meta__.state == :deleted))

  @doc """
  Title of an embedded quiz, or its current question while they are stepped through.
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
  Classes for an embedded quiz option; the correct one shows only once results are out.
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
      |> assign_new(:interaction_only, fn ->
        socket.assigns[:live_action] == :interaction
      end)
      |> assign_new(:pinned_poll_id, fn -> nil end)
      |> assign_new(:pinned_quiz_id, fn -> nil end)
      |> assign_new(:pinned_form_id, fn -> nil end)
      |> assign_new(:embed_style, fn -> embed_style(%{}) end)
      |> assign_new(:embed_show, fn -> "interaction" end)
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

  defp presenter_reply_count(assigns) do
    ~H"""
    <p class={[
      "font-semibold text-gray-500",
      if(@iframe, do: "mt-2 text-xs", else: "mt-4 text-base")
    ]}>
      {ngettext("%{count} reply", "%{count} replies", @count)}
    </p>
    """
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
       |> assign(:current_poll, poll)}
    else
      {:noreply,
       socket
       |> assign(:current_poll, nil)}
    end
  end

  @impl true
  def handle_info({:poll_deleted, _poll}, socket) do
    {:noreply,
     socket
     |> assign(:current_poll, nil)}
  end

  # A block pinned to a form ignores changes to other forms.
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
     |> assign(:current_quiz, quiz)}
  end

  @impl true
  def handle_info({:quiz_deleted, _quiz}, socket) do
    {:noreply,
     socket
     |> assign(:current_quiz, nil)}
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
     |> assign(:current_poll, interaction)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Embed{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_embed, interaction)
     |> assign(:current_poll, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Form{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_form, interaction)
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_quiz, nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Quiz{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_quiz, interaction)
     |> assign(:current_poll, nil)
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
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)}
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

  # Revoking the link or ending the event sends open embeds to a path the token
  # plug rejects, so the frame shows its 404. The path is fixed because the raw
  # token is kept out of the assigns.
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

  # A pinned embed shows only the interaction its link names, whatever the deck does.
  defp poll_at_position(%{assigns: %{pinned_poll_id: id, event: event}} = socket)
       when is_integer(id) do
    assign(socket, :current_poll, Claper.Polls.get_poll_for_event(id, event.id))
  end

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
      assign(socket, :current_poll, poll)
    end
  end

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

  # Read here so the template does not query on every render.
  defp assign_form(socket, form) do
    socket
    |> assign(:current_form, form)
    |> assign(:form_answers, form_answers(form))
  end

  @doc """
  Returns every non-blank answer to a form as a string, one per field, newest
  submission first and fields in name order.
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

  defp embed_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with embed <-
           Claper.Embeds.get_embed_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign(:current_embed, embed)
    end
  end

  # Embeds do not always mount the quiz component, and updating a missing
  # component raises.
  defp move_to_quiz_question(socket, idx) do
    if quiz_component_mounted?(socket) do
      send_update(
        ClaperWeb.EventLive.ManageableQuizComponent,
        id: "#{socket.assigns.current_quiz.id}-quiz",
        current_question_idx: idx
      )
    end

    {:noreply, assign(socket, :current_question_idx, idx)}
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

    socket |> assign(:current_quiz, quiz) |> assign(:current_question_idx, 0)
  end

  defp quiz_at_position(%{assigns: %{pinned_poll_id: id}} = socket) when is_integer(id) do
    socket |> assign(:current_quiz, nil) |> assign(:current_question_idx, 0)
  end

  defp quiz_at_position(%{assigns: %{pinned_form_id: id}} = socket) when is_integer(id) do
    socket |> assign(:current_quiz, nil) |> assign(:current_question_idx, 0)
  end

  defp quiz_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with quiz <-
           Claper.Quizzes.get_quiz_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign(:current_quiz, quiz) |> assign(:current_question_idx, 0)
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
  """
  def current_slide_url(presentation_file, position) do
    presentation_file
    |> Claper.Presentations.get_slide_urls()
    |> Enum.at(position)
  end
end
