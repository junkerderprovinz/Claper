# Claper in PowerPoint

Keep your PowerPoint file as the presentation and let Claper deliver only the
interaction onto a slide of it. Nothing is converted and nothing is uploaded, so
editing the deck goes on exactly as before.

There are two add-ins because Office needs one manifest per kind:

- **Claper** is the sidebar. It writes the polls and quizzes and hands you one
  link for the whole deck.
- **Claper on a slide** is the block you place on a slide. Each block picks what
  it shows: a poll, a quiz, the messages from the room, or how to join.

## Turning the feature on

The server refuses every embed link until an operator names the origins that may
frame it, so this is the switch for the whole feature:

```
PRESENTER_EMBED_FRAME_ANCESTORS="https://*.officeapps.live.com"
```

Desktop PowerPoint frames the pages from `officeapps.live.com`. Add your own
origins separated by spaces if you also embed elsewhere.

## Installing

**Do not edit these files by hand.** A running Claper serves both of them with
its own address already in place, at `/addin`. The copies here are the templates
it fills in, and they are also what you would edit if you wanted to change
something about the add-ins themselves.

Send people to `https://your-claper/addin`. That page carries the two links and
both routes below.

**Your administrator, once, for everyone.** In the Microsoft 365 admin center:
Settings, Integrated apps, Upload custom apps. It takes a **URL** as well as a
file, so paste `https://your-claper/addin/manifest/sidebar.xml`, choose who gets
it, and repeat with `.../slide.xml`. Allow up to a day before it appears.

**Or just for yourself.** Download both files into a folder and share it (right
click, Properties, Sharing). In PowerPoint: File, Options, Trust Center, Trust
Center Settings, Trusted Add-in Catalogs. Paste the folder's network path
(`\\MACHINE\folder`), press Add catalog, tick "Show in Menu", restart PowerPoint.
Then Insert, Add-ins, My Add-ins, Shared Folder.

On Mac, put the files in
`~/Library/Containers/com.microsoft.Powerpoint/Data/Documents/wef` instead.

**Why there is no single add-in in the store for everyone.** An Office manifest
carries the add-in's address as a fixed string, and Claper's API sends no CORS
headers, so a copy hosted centrally could not talk to your server at all. Every
instance therefore hands out manifests naming itself.

## Using it

1. Open the sidebar and connect it: your Claper address, and the sidebar key
   from your event's settings. The key can create and delete questions, so it
   stays on this machine and never inside the file.
2. Write your polls and quizzes in the sidebar.
3. On the **On slides** tab, press **Put the code on this slide**. That is a
   picture, so it lands on the slide you have open. Without it nobody in the
   room knows how to answer.
4. On the same tab, create the slide link once. It only reads, so it is saved
   into the presentation and travels with it.
5. Insert **Claper on a slide** wherever you want a live answer, and pick what
   that block shows. It finds the link on its own.

## Things that are PowerPoint's and not ours

- **The frame and the soft shadow along the top edge of a live block** are drawn
  by PowerPoint around every content add-in. Fill, Outline and Effects are
  greyed out on such an object, and neither manifest nor CSS can reach it. A
  block whose content does not need to be live is better inserted as a picture,
  which is why the joining code is one.
- **Duplicating a slide** that holds a block: on PowerPoint for the web the copy
  keeps the original's instance id (office-js#2765), so the two can read each
  other's choice. Insert a second block instead of copying one.
- **Handing the link to the blocks** uses a presentation tag, which needs
  PowerPointApi 1.3. Where that is missing the sidebar says so and the link has
  to be pasted into each block once.

## What ends up inside the .pptx

The slide link and each block's choice are stored in the presentation file.
Anyone who unzips a .pptx can read them, so treat a deck you send out as
carrying its slide link in the clear. That is why the link only reads, and why
the sidebar key is kept on your machine instead.

## What the two keys can do

| | Sidebar key | Slide link |
|---|---|---|
| Create, edit and delete questions | yes | no |
| Read the presenter view | no | yes |
| Belongs in the .pptx | **no** | yes |

Both are revoked from the event's settings, and both stop working the moment the
event ends.
