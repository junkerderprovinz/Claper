defmodule ClaperWeb.AddinStrings do
  @moduledoc """
  Everything the two PowerPoint pages say, in whatever language Office is set to.

  Those pages are static files, which is why they stayed English whatever the
  rest of Claper was set to: nothing on them ever passed through gettext. They
  are still static and still carry their English text. What changed is that the
  English text is now also the key: the page fetches this map and swaps the text
  it finds against it.

  Keeping English as the key is what lets the markup stay untouched and lets a
  missing translation fall back to something a person can read rather than to a
  bare identifier. Each entry names its string twice, once as the key and once
  inside `gettext/1`, so `mix gettext.extract` finds every one of them.
  """

  use Gettext, backend: ClaperWeb.Gettext

  @doc """
  The languages the add-in can speak, which is whatever Claper itself speaks.
  """
  def locales, do: Gettext.known_locales(ClaperWeb.Gettext)

  @doc """
  Every string in every language, as `%{locale => %{english => translated}}`.

  All at once rather than one language per request, because the page can only
  ask after Office is ready and a second round trip there would show English
  first and then blink. It is a few kilobytes.
  """
  def all do
    Map.new(locales(), fn locale ->
      {locale, Gettext.with_locale(ClaperWeb.Gettext, locale, &strings/0)}
    end)
  end

  defp strings do
    %{
      # The welcome page
      "Bring Claper into PowerPoint" => gettext("Bring Claper into PowerPoint"),
      "Write the questions here, keep the deck as your own PowerPoint file, and let the answers come in live on the slide." =>
        gettext(
          "Write the questions here, keep the deck as your own PowerPoint file, and let the answers come in live on the slide."
        ),
      "Connect once" => gettext("Connect once"),
      "Your Claper address and the sidebar key from your event." =>
        gettext("Your Claper address and the sidebar key from your event."),
      "Write questions" => gettext("Write questions"),
      "Polls and quizzes, created on your event straight away." =>
        gettext("Polls and quizzes, created on your event straight away."),
      "Put the join code on a slide" => gettext("Put the join code on a slide"),
      "One button. Without it nobody in the room can answer." =>
        gettext("One button. Without it nobody in the room can answer."),
      "Put the answers on slides" => gettext("Put the answers on slides"),
      "One link for the whole deck. Each block then picks what it shows." =>
        gettext("One link for the whole deck. Each block then picks what it shows."),
      "Get started" => gettext("Get started"),

      # Connecting
      "Connect" => gettext("Connect"),
      "Claper address" => gettext("Claper address"),
      "Your key" => gettext("Your key"),
      "From your account settings. It can create and delete, so it stays on this computer and never inside a presentation. A key from a single event's settings works too." =>
        gettext(
          "From your account settings. It can create and delete, so it stays on this computer and never inside a presentation. A key from a single event's settings works too."
        ),
      "Back" => gettext("Back"),
      "Checking…" => gettext("Checking…"),
      "Both are needed." => gettext("Both are needed."),

      # Choosing an event for this presentation
      "This presentation" => gettext("This presentation"),
      "Give it an event of its own and its questions stay its own. The choice is saved in the file, so it is the same on any computer that opens it." =>
        gettext(
          "Give it an event of its own and its questions stay its own. The choice is saved in the file, so it is the same on any computer that opens it."
        ),
      "Start a new event" => gettext("Start a new event"),
      "Name of your talk" => gettext("Name of your talk"),
      "Create it" => gettext("Create it"),
      "Or use one you already have" => gettext("Or use one you already have"),
      "Use this one" => gettext("Use this one"),
      "You have no events yet." => gettext("You have no events yet."),
      "Give it a name." => gettext("Give it a name."),
      "Creating…" => gettext("Creating…"),
      "This presentation could not remember its event. Save the file, then reconnect." =>
        gettext("This presentation could not remember its event. Save the file, then reconnect."),

      # The working view
      "Your event" => gettext("Your event"),
      "Change" => gettext("Change"),
      "Start" => gettext("Start"),
      "Connection" => gettext("Connection"),
      "Polls" => gettext("Polls"),
      "Quizzes" => gettext("Quizzes"),
      "On slides" => gettext("On slides"),
      "Reload" => gettext("Reload"),
      "Loading…" => gettext("Loading…"),
      "Edit" => gettext("Edit"),
      "Delete" => gettext("Delete"),
      "Keep it" => gettext("Keep it"),
      "Save" => gettext("Save"),
      "Cancel" => gettext("Cancel"),
      "For PowerPoint" => gettext("For PowerPoint"),
      "Claper slide" => gettext("Claper slide"),
      "Put on its own slide" => gettext("Put on its own slide"),
      "Building the slide…" => gettext("Building the slide…"),
      "Added as a new slide at the end." => gettext("Added as a new slide at the end."),
      "Put one Claper block on a slide first. Every slide after that is copied from it." =>
        gettext(
          "Put one Claper block on a slide first. Every slide after that is copied from it."
        ),
      "already on the deck inside Claper" => gettext("already on the deck inside Claper"),
      "answers so far" => gettext("answers so far"),
      "Delete this question? The answers already given go with it." =>
        gettext("Delete this question? The answers already given go with it."),
      "Delete this quiz? The answers already given go with it." =>
        gettext("Delete this quiz? The answers already given go with it."),

      # Polls
      "Question" => gettext("Question"),
      "How was it?" => gettext("How was it?"),
      "Answers, one per line" => gettext("Answers, one per line"),
      "Create poll" => gettext("Create poll"),
      "No polls for this presentation yet." => gettext("No polls for this presentation yet."),
      "The question is missing." => gettext("The question is missing."),
      "At least two answers." => gettext("At least two answers."),
      "Created. Pick it on a slide." => gettext("Created. Pick it on a slide."),
      "Changing the answers clears the votes already given for this question." =>
        gettext("Changing the answers clears the votes already given for this question."),

      # Quizzes
      "Quiz name" => gettext("Quiz name"),
      "Round one" => gettext("Round one"),
      "Add another question" => gettext("Add another question"),
      "Create quiz" => gettext("Create quiz"),
      "Right answers stay hidden on the slide until you release the results in Claper." =>
        gettext("Right answers stay hidden on the slide until you release the results in Claper."),
      "No quizzes for this presentation yet." => gettext("No quizzes for this presentation yet."),
      "Add answer" => gettext("Add answer"),
      "Remove" => gettext("Remove"),
      "Right" => gettext("Right"),
      "The quiz needs a name." => gettext("The quiz needs a name."),
      "A quiz needs at least one question." => gettext("A quiz needs at least one question."),
      "Saving rebuilds the questions, which clears the answers already given for this quiz." =>
        gettext(
          "Saving rebuilds the questions, which clears the answers already given for this quiz."
        ),

      # On slides
      "How people join" => gettext("How people join"),
      "Put this on an early slide, otherwise nobody in the room knows how to answer. It is a picture, so it goes straight onto the slide you have open." =>
        gettext(
          "Put this on an early slide, otherwise nobody in the room knows how to answer. It is a picture, so it goes straight onto the slide you have open."
        ),
      "Put the code on this slide" => gettext("Put the code on this slide"),
      "Drawing the code…" => gettext("Drawing the code…"),
      "Putting it on the slide…" => gettext("Putting it on the slide…"),
      "Done. It landed on the slide you have open." =>
        gettext("Done. It landed on the slide you have open."),
      "One link for the whole deck" => gettext("One link for the whole deck"),
      "Made once, then every Claper object you put on a slide finds it by itself and only asks what that slide should show. The link only reads, so it is safe inside the file." =>
        gettext(
          "Made once, then every Claper object you put on a slide finds it by itself and only asks what that slide should show. The link only reads, so it is safe inside the file."
        ),
      "No link yet" => gettext("No link yet"),
      "Copy" => gettext("Copy"),
      "Copied" => gettext("Copied"),
      "Create link" => gettext("Create link"),
      "Asking Claper…" => gettext("Asking Claper…"),
      "Ready. Blocks you put on slides pick it up on their own." =>
        gettext("Ready. Blocks you put on slides pick it up on their own."),
      "Insert a live block" => gettext("Insert a live block"),
      "Insert > Add-ins > My Add-ins" => gettext("Insert > Add-ins > My Add-ins"),
      "Pick \"Claper on a slide\"." => gettext("Pick \"Claper on a slide\"."),
      "Choose what it shows" => gettext("Choose what it shows"),
      "It already knows the link." => gettext("It already knows the link."),
      "Repeat per slide" => gettext("Repeat per slide"),
      "Insert another one wherever you want a live answer." =>
        gettext("Insert another one wherever you want a live answer."),

      # The block on a slide
      "Claper on this slide" => gettext("Claper on this slide"),
      "Paste the link from the Claper sidebar once. It is stored with this presentation, so everyone who opens the file sees the same thing." =>
        gettext(
          "Paste the link from the Claper sidebar once. It is stored with this presentation, so everyone who opens the file sees the same thing."
        ),
      "Slide link" => gettext("Slide link"),
      "Continue" => gettext("Continue"),
      "Show on this slide" => gettext("Show on this slide"),
      "Change how it looks" => gettext("Change how it looks"),
      "Text" => gettext("Text"),
      "Dark text" => gettext("Dark text"),
      "Light text" => gettext("Light text"),
      "Background" => gettext("Background"),
      "Card" => gettext("Card"),
      "Transparent" => gettext("Transparent"),
      "Bars" => gettext("Bars"),
      "Slightly rounded" => gettext("Slightly rounded"),
      "Square" => gettext("Square"),
      "Fully rounded" => gettext("Fully rounded"),
      "Shadow" => gettext("Shadow"),
      "None" => gettext("None"),
      "Soft shadow" => gettext("Soft shadow"),
      "Show it" => gettext("Show it"),
      "Use a different link" => gettext("Use a different link"),
      "How to join (QR code and code)" => gettext("How to join (QR code and code)"),
      "Messages from the audience" => gettext("Messages from the audience"),
      "Whatever Claper is showing right now" => gettext("Whatever Claper is showing right now"),
      "That does not look like a Claper slide link." =>
        gettext("That does not look like a Claper slide link."),
      "This slide link no longer works. Ask the Claper sidebar for the current one." =>
        gettext("This slide link no longer works. Ask the Claper sidebar for the current one.")
    }
  end
end
