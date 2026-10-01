defmodule ClaperWeb.AddinStrings do
  @moduledoc """
  Translations for the static PowerPoint add-in pages, keyed by their English
  text.

  Each string appears twice, as the key and inside `gettext/1`, so that
  `mix gettext.extract` finds it. Product names are left out.
  """

  use Gettext, backend: ClaperWeb.Gettext

  @doc """
  Returns the locales Claper has translations for.
  """
  def locales, do: Gettext.known_locales(ClaperWeb.Gettext)

  @doc """
  Returns every string in every locale, as `%{locale => %{english => translated}}`.
  """
  def all do
    Map.new(locales(), fn locale ->
      {locale, Gettext.with_locale(ClaperWeb.Gettext, locale, &strings/0)}
    end)
  end

  @doc """
  Returns every string in the current locale, as `%{english => translated}`.
  """
  def strings do
    %{
      # The welcome page
      "Bring Claper into PowerPoint" => gettext("Bring Claper into PowerPoint"),
      "Write the questions here, keep the deck as your own PowerPoint file, and let the answers come in live on the slide." =>
        gettext(
          "Write the questions here, keep the deck as your own PowerPoint file, and let the answers come in live on the slide."
        ),
      "Connect once" => gettext("Connect once"),
      "Your Claper address and the sidebar key from your account." =>
        gettext("Your Claper address and the sidebar key from your account."),
      "Write questions" => gettext("Write questions"),
      "Polls, quizzes and open questions, created straight away." =>
        gettext("Polls, quizzes and open questions, created straight away."),
      "Put the join code on a slide" => gettext("Put the join code on a slide"),
      "One button. Without it nobody in the room can answer." =>
        gettext("One button. Without it nobody in the room can answer."),
      "Put the answers on slides" => gettext("Put the answers on slides"),
      "One button per question, on this slide or on a new one." =>
        gettext("One button per question, on this slide or on a new one."),
      "Get started" => gettext("Get started"),

      # Connecting
      "Connect" => gettext("Connect"),
      "Claper address" => gettext("Claper address"),
      "Your key" => gettext("Your key"),
      "Account settings, PowerPoint" => gettext("Account settings, PowerPoint"),
      "From your account settings. It can create and delete, so it stays on this computer and never inside a presentation. That is the key that lets each presentation have a talk of its own. A key from a single event also connects, but then every presentation you open shows that one talk and can never start its own." =>
        gettext(
          "From your account settings. It can create and delete, so it stays on this computer and never inside a presentation. That is the key that lets each presentation have a talk of its own. A key from a single event also connects, but then every presentation you open shows that one talk and can never start its own."
        ),
      "Back" => gettext("Back"),
      "Checking…" => gettext("Checking…"),
      "Both are needed." => gettext("Both are needed."),

      # Choosing an event for this presentation
      "This presentation" => gettext("This presentation"),
      "Every presentation gets an event of its own, so it never shows the questions of another talk. The choice is saved in the file, so it is the same on any computer that opens it." =>
        gettext(
          "Every presentation gets an event of its own, so it never shows the questions of another talk. The choice is saved in the file, so it is the same on any computer that opens it."
        ),
      "Start a new event" => gettext("Start a new event"),
      "Name of your talk" => gettext("Name of your talk"),
      "Create it" => gettext("Create it"),
      "Or use one you already have" => gettext("Or use one you already have"),
      "Use this one" => gettext("Use this one"),
      "You have no events yet." => gettext("You have no events yet."),
      "Give it a name." => gettext("Give it a name."),
      "Creating…" => gettext("Creating…"),
      "Setting up this presentation…" => gettext("Setting up this presentation…"),
      # What a deck that has never been saved is called, with the date after it.
      "New presentation" => gettext("New presentation"),
      # Labels the event, shown under the file name.
      "Talk:" => gettext("Talk:"),
      # Shown when an event scoped key cannot create an event for the deck.
      "Set this up once" => gettext("Set this up once"),
      "Create key" => gettext("Create key"),
      "A personal key fixes it for good. Four steps, once:" =>
        gettext("A personal key fixes it for good. Four steps, once:"),
      "Open Claper in your browser" => gettext("Open Claper in your browser"),
      "The same address this add-in uses." => gettext("The same address this add-in uses."),
      "Your initials, bottom left, then Settings" =>
        gettext("Your initials, bottom left, then Settings"),
      "Scroll to the PowerPoint section." => gettext("Scroll to the PowerPoint section."),
      "It is shown once. Copy it." => gettext("It is shown once. Copy it."),
      "Paste it below" => gettext("Paste it below"),
      "From then on every presentation gets a talk of its own, named after the file." =>
        gettext("From then on every presentation gets a talk of its own, named after the file."),
      "Paste a personal key" => gettext("Paste a personal key"),
      "Use this key" => gettext("Use this key"),
      "The deck link, and placing the first block by hand" =>
        gettext("The deck link, and placing the first block by hand"),
      "The key this add-in is connected with belongs to one single talk. It cannot give this presentation a talk of its own, and until it has one, nothing is shown here: another talk's questions under this presentation's name is the one thing this must never do." =>
        gettext(
          "The key this add-in is connected with belongs to one single talk. It cannot give this presentation a talk of its own, and until it has one, nothing is shown here: another talk's questions under this presentation's name is the one thing this must never do."
        ),
      "This presentation could not remember its event. Save the file, then reconnect." =>
        gettext("This presentation could not remember its event. Save the file, then reconnect."),

      # The working view
      "Change" => gettext("Change"),
      "Start" => gettext("Start"),
      "Connection" => gettext("Connection"),
      "Guide" => gettext("Guide"),
      "Settings" => gettext("Settings"),
      "Polls" => gettext("Polls"),
      "Quizzes" => gettext("Quizzes"),
      "Open" => gettext("Open"),
      "Joining" => gettext("Joining"),
      "Reload" => gettext("Reload"),
      "Loading…" => gettext("Loading…"),
      "Edit" => gettext("Edit"),
      "Delete" => gettext("Delete"),
      "Keep it" => gettext("Keep it"),
      "Save" => gettext("Save"),
      "Cancel" => gettext("Cancel"),
      "For PowerPoint" => gettext("For PowerPoint"),
      "Claper slide" => gettext("Claper slide"),
      "already on the deck inside Claper" => gettext("already on the deck inside Claper"),
      "answers so far" => gettext("answers so far"),

      # Putting a question on a slide
      "On this slide" => gettext("On this slide"),
      "Puts a live block on the slide you have open, keeping what is on it." =>
        gettext("Puts a live block on the slide you have open, keeping what is on it."),
      "New slide" => gettext("New slide"),
      "Adds a slide at the end showing this question." =>
        gettext("Adds a slide at the end showing this question."),
      "Building the slide…" => gettext("Building the slide…"),
      "Added as a new slide at the end." => gettext("Added as a new slide at the end."),
      "Done. It is on the slide you had open." =>
        gettext("Done. It is on the slide you had open."),
      "Open the slide you want it on first." => gettext("Open the slide you want it on first."),

      # Polls
      "What a poll is for" => gettext("What a poll is for"),
      "You give the answers, the room picks one. No answer is right, and the bars grow while people vote. Write it here, then put it on a slide with one button. The room answers on their phones after scanning the join code." =>
        gettext(
          "You give the answers, the room picks one. No answer is right, and the bars grow while people vote. Write it here, then put it on a slide with one button. The room answers on their phones after scanning the join code."
        ),
      "Question" => gettext("Question"),
      "How was it?" => gettext("How was it?"),
      "Answers" => gettext("Answers"),
      "Answer" => gettext("Answer"),
      "Create poll" => gettext("Create poll"),
      "No polls for this presentation yet." => gettext("No polls for this presentation yet."),
      "The question is missing." => gettext("The question is missing."),
      "At least two answers." => gettext("At least two answers."),
      "Created. Put it on a slide below." => gettext("Created. Put it on a slide below."),
      "Changing the answers clears the votes already given for this question." =>
        gettext("Changing the answers clears the votes already given for this question."),
      "Delete this question? The answers already given go with it." =>
        gettext("Delete this question? The answers already given go with it."),

      # Quizzes
      "How a quiz differs from a poll" => gettext("How a quiz differs from a poll"),
      "A quiz has right answers and can hold several questions in a row. Tick the right one while you write it. On the slide every answer looks the same until you release the results in Claper, so nobody in the room can read the answer off the wall." =>
        gettext(
          "A quiz has right answers and can hold several questions in a row. Tick the right one while you write it. On the slide every answer looks the same until you release the results in Claper, so nobody in the room can read the answer off the wall."
        ),
      "Quiz name" => gettext("Quiz name"),
      "Round one" => gettext("Round one"),
      "What is the capital of France?" => gettext("What is the capital of France?"),
      "Add another question" => gettext("Add another question"),
      "Create quiz" => gettext("Create quiz"),
      "No quizzes for this presentation yet." => gettext("No quizzes for this presentation yet."),
      "Add answer" => gettext("Add answer"),
      "Remove" => gettext("Remove"),
      "Right" => gettext("Right"),
      "The quiz needs a name." => gettext("The quiz needs a name."),
      "A quiz needs at least one question." => gettext("A quiz needs at least one question."),
      "A question is missing its text." => gettext("A question is missing its text."),
      "Every question needs at least two answers." =>
        gettext("Every question needs at least two answers."),
      "Every question needs one answer ticked as right." =>
        gettext("Every question needs one answer ticked as right."),
      "Saving rebuilds the questions, which clears the answers already given for this quiz." =>
        gettext(
          "Saving rebuilds the questions, which clears the answers already given for this quiz."
        ),
      "Delete this quiz? The answers already given go with it." =>
        gettext("Delete this quiz? The answers already given go with it."),

      # Open questions
      "What an open question is for" => gettext("What an open question is for"),
      "Nothing to pick from: people write their own answer and it appears on your slide as it arrives. Use it when you do not know the answers yet, for gathering questions, or for one word each on how the room is feeling." =>
        gettext(
          "Nothing to pick from: people write their own answer and it appears on your slide as it arrives. Use it when you do not know the answers yet, for gathering questions, or for one word each on how the room is feeling."
        ),
      "Usually one box is enough. Add a second when you want two things at once, say a name and a question." =>
        gettext(
          "Usually one box is enough. Add a second when you want two things at once, say a name and a question."
        ),
      "What should we talk about?" => gettext("What should we talk about?"),
      "Boxes people fill in" => gettext("Boxes people fill in"),
      "Name of the box" => gettext("Name of the box"),
      "Your answer" => gettext("Your answer"),
      "Add box" => gettext("Add box"),
      "At least one box." => gettext("At least one box."),
      "Create open question" => gettext("Create open question"),
      "Open questions" => gettext("Open questions"),
      "No open questions for this presentation yet." =>
        gettext("No open questions for this presentation yet."),
      "Delete this open question? What people wrote goes with it." =>
        gettext("Delete this open question? What people wrote goes with it."),

      # On slides
      "How people join" => gettext("How people join"),
      "Put this on an early slide, otherwise nobody in the room knows how to answer. It is a picture, so it goes straight onto the slide you have open." =>
        gettext(
          "Put this on an early slide, otherwise nobody in the room knows how to answer. It is a picture, so it goes straight onto the slide you have open."
        ),
      "Show the web address as well" => gettext("Show the web address as well"),
      "Off by default: the code is scanned, and the address underneath is one more thing on your slide. Turn it on for a room where phones are not a given." =>
        gettext(
          "Off by default: the code is scanned, and the address underneath is one more thing on your slide. Turn it on for a room where phones are not a given."
        ),
      "Put the code on this slide" => gettext("Put the code on this slide"),
      "Drawing the code…" => gettext("Drawing the code…"),
      "Putting it on the slide…" => gettext("Putting it on the slide…"),
      "Done. It landed on the slide you have open." =>
        gettext("Done. It landed on the slide you have open."),
      "Add a welcome slide" => gettext("Add a welcome slide"),
      "The welcome slide is a whole slide made for you: the join code big enough to read from the back, the code as a picture beside it, and one line telling the room what to do. Yours afterwards, so move and restyle it as you like." =>
        gettext(
          "The welcome slide is a whole slide made for you: the join code big enough to read from the back, the code as a picture beside it, and one line telling the room what to do. Yours afterwards, so move and restyle it as you like."
        ),
      "This PowerPoint is too old to add a slide from here. Add one yourself and use the button above." =>
        gettext(
          "This PowerPoint is too old to add a slide from here. Add one yourself and use the button above."
        ),
      "PowerPoint did not add the slide." => gettext("PowerPoint did not add the slide."),
      "Added at the end. Move it to the front and it is your opening slide." =>
        gettext("Added at the end. Move it to the front and it is your opening slide."),
      "Added at the end. This PowerPoint cannot write the text, so type the code beside the picture." =>
        gettext(
          "Added at the end. This PowerPoint cannot write the text, so type the code beside the picture."
        ),
      "Join in" => gettext("Join in"),
      "Open the camera, point it at the code, answer on your phone." =>
        gettext("Open the camera, point it at the code, answer on your phone."),

      # The standard look for the whole deck
      "How new blocks look" => gettext("How new blocks look"),
      "Set once here and every block you add afterwards starts this way. A block you have already placed keeps what it has, and each one can still be changed on its own slide." =>
        gettext(
          "Set once here and every block you add afterwards starts this way. A block you have already placed keeps what it has, and each one can still be changed on its own slide."
        ),
      "Background behind a block" => gettext("Background behind a block"),
      "PowerPoint always paints something behind a live block: a web object on a slide cannot be see-through, and Microsoft has turned that request down. So the block paints the colour you pick here instead. Set it to your slide's own colour and the edge disappears." =>
        gettext(
          "PowerPoint always paints something behind a live block: a web object on a slide cannot be see-through, and Microsoft has turned that request down. So the block paints the colour you pick here instead. Set it to your slide's own colour and the edge disappears."
        ),
      "Soft shadow under the block" => gettext("Soft shadow under the block"),
      "Save as the standard" => gettext("Save as the standard"),
      "Back to plain" => gettext("Back to plain"),
      "Saving…" => gettext("Saving…"),
      "Saved. New blocks start this way." => gettext("Saved. New blocks start this way."),
      "This PowerPoint cannot store it in the file. Set it on each block instead." =>
        gettext("This PowerPoint cannot store it in the file. Set it on each block instead."),
      "Back to plain. New blocks look the way Claper draws them." =>
        gettext("Back to plain. New blocks look the way Claper draws them."),

      # Is this still the same talk?
      "Is this the same talk?" => gettext("Is this the same talk?"),
      "This file was set up as the event below, but it was called something else then. A presentation saved under a new name is usually a new talk, and a new talk with the old event would show the old talk's questions to the new room." =>
        gettext(
          "This file was set up as the event below, but it was called something else then. A presentation saved under a new name is usually a new talk, and a new talk with the old event would show the old talk's questions to the new room."
        ),
      "Same talk, keep it" => gettext("Same talk, keep it"),
      "New talk, start fresh" => gettext("New talk, start fresh"),
      "Starting fresh gives this file its own event and its own link. Nothing is deleted: the old talk keeps everything it had." =>
        gettext(
          "Starting fresh gives this file its own event and its own link. Nothing is deleted: the old talk keeps everything it had."
        ),
      "One link for the whole deck" => gettext("One link for the whole deck"),
      "Made for you the moment this presentation gets its event, and stored in the file. A block placed by the buttons on a question is handed the link directly, so it never asks. A block you insert by hand asks once, and this is the link to paste." =>
        gettext(
          "Made for you the moment this presentation gets its event, and stored in the file. A block placed by the buttons on a question is handed the link directly, so it never asks. A block you insert by hand asks once, and this is the link to paste."
        ),
      "No link yet" => gettext("No link yet"),
      "Copy" => gettext("Copy"),
      "Copied" => gettext("Copied"),
      "Make a new link" => gettext("Make a new link"),
      "A new link replaces the old one everywhere. Only needed if the old one got out." =>
        gettext("A new link replaces the old one everywhere. Only needed if the old one got out."),
      "Asking Claper…" => gettext("Asking Claper…"),
      "Ready. Blocks you put on slides pick it up on their own." =>
        gettext("Ready. Blocks you put on slides pick it up on their own."),
      "Ready. This PowerPoint cannot hand it over on its own, so paste it into each Claper object." =>
        gettext(
          "Ready. This PowerPoint cannot hand it over on its own, so paste it into each Claper object."
        ),
      "The first live block" => gettext("The first live block"),
      "The buttons on each question copy a block that already exists in this file, so the very first one has to be inserted by hand. Once one is in, you never have to do this again." =>
        gettext(
          "The buttons on each question copy a block that already exists in this file, so the very first one has to be inserted by hand. Once one is in, you never have to do this again."
        ),
      "Insert > Add-ins > My Add-ins" => gettext("Insert > Add-ins > My Add-ins"),
      "Pick \"Claper on a slide\"." => gettext("Pick \"Claper on a slide\"."),
      "Paste the link from above" => gettext("Paste the link from above"),
      "Then pick what that slide should show." =>
        gettext("Then pick what that slide should show."),
      "The frame around a live block, and the soft shadow along its top edge, are PowerPoint's own and cannot be turned off from here. A picture has neither, which is why the joining code is one." =>
        gettext(
          "The frame around a live block, and the soft shadow along its top edge, are PowerPoint's own and cannot be turned off from here. A picture has neither, which is why the joining code is one."
        ),

      # The block on a slide
      "Claper on this slide" => gettext("Claper on this slide"),
      # The frame's accessible name.
      "Claper interaction" => gettext("Claper interaction"),
      "Paste the link from the Claper sidebar once. It is stored with this presentation, so everyone who opens the file sees the same thing." =>
        gettext(
          "Paste the link from the Claper sidebar once. It is stored with this presentation, so everyone who opens the file sees the same thing."
        ),
      "Slide link" => gettext("Slide link"),
      "Continue" => gettext("Continue"),
      "Show on this slide" => gettext("Show on this slide"),
      "Colours, background and more" => gettext("Colours, background and more"),
      "Back to the standard look" => gettext("Back to the standard look"),
      "Set back to the standard look. Save it below to apply." =>
        gettext("Set back to the standard look. Save it below to apply."),
      "This presentation now belongs to a different event. Choose what this slide shows." =>
        gettext(
          "This presentation now belongs to a different event. Choose what this slide shows."
        ),
      # {name} is filled in by the page; gettext leaves single braces alone.
      "Connected to {name}. Choose what this slide shows." =>
        gettext("Connected to {name}. Choose what this slide shows."),
      "Choose what this slide shows." => gettext("Choose what this slide shows."),
      "PowerPoint could not save this:" => gettext("PowerPoint could not save this:"),
      "PowerPoint could not save this." => gettext("PowerPoint could not save this."),
      "Text" => gettext("Text"),
      "Dark text" => gettext("Dark text"),
      "Light text" => gettext("Light text"),
      # Whether the block is drawn on a card.
      "Shape" => gettext("Shape"),
      "Plain" => gettext("Plain"),
      "Card" => gettext("Card"),
      "Background behind this block" => gettext("Background behind this block"),
      "PowerPoint always paints something behind a live block. Set this to your slide's colour and the edge disappears." =>
        gettext(
          "PowerPoint always paints something behind a live block. Set this to your slide's colour and the edge disappears."
        ),
      # How round the bars are drawn.
      "Bars" => gettext("Bars"),
      "Slightly rounded" => gettext("Slightly rounded"),
      "Square" => gettext("Square"),
      "Fully rounded" => gettext("Fully rounded"),
      "Shadow" => gettext("Shadow"),
      "None" => gettext("None"),
      "Soft shadow" => gettext("Soft shadow"),
      # What is shown at the end of a bar.
      "Numbers at the bar" => gettext("Numbers at the bar"),
      "Percent and count" => gettext("Percent and count"),
      "Percent only" => gettext("Percent only"),
      "Count only" => gettext("Count only"),
      "Use my own colours" => gettext("Use my own colours"),
      "Text colour" => gettext("Text colour"),
      "Bar colour" => gettext("Bar colour"),
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
