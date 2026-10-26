# Claper in PowerPoint

The presentation stays a PowerPoint file and Claper adds the interaction to its
slides. Nothing is converted or uploaded.

There are two add-ins, because a manifest holds one add-in of one kind:

- **Claper** is the sidebar. It is where you write polls and quizzes, and it
  creates one link for the whole deck.
- **Claper on a slide** is a block placed on a slide. Each block shows one
  thing: a poll, a quiz, the messages from the room, or how to join.

## Turning the feature on

The server refuses every embed link until the origins allowed to frame it are
set:

```
PRESENTER_EMBED_FRAME_ANCESTORS="https://*.officeapps.live.com"
```

Desktop PowerPoint loads the pages from `officeapps.live.com`. To embed them
elsewhere as well, add more origins separated by spaces.

## Installing

A running Claper serves both manifests with its own address filled in, so the
files here are only templates. Send people to `https://your-claper/addin`,
which has both links and the two routes below.

**For everyone, by an administrator.** In the Microsoft 365 admin center go to
Settings, Integrated apps, Upload custom apps. It accepts a URL: paste
`https://your-claper/addin/manifest/sidebar.xml`, choose who gets it, and repeat
with `.../slide.xml`. It can take up to a day to appear.

**For yourself.** Download both files into a folder and share it (right click,
Properties, Sharing). In PowerPoint open File, Options, Trust Center, Trust
Center Settings, Trusted Add-in Catalogs. Paste the folder's network path
(`\\MACHINE\folder`), press Add catalog, tick "Show in Menu" and restart
PowerPoint. The add-ins are then under Insert, Add-ins, My Add-ins, Shared
Folder.

On Mac, put the files in
`~/Library/Containers/com.microsoft.Powerpoint/Data/Documents/wef` instead.

There is no single add-in in the Office store because a manifest carries the
add-in's address as a fixed string and Claper's API sends no CORS headers. Each
server hands out manifests that name itself.

## Using it

1. Open the sidebar and connect it with your Claper address and the sidebar key
   from your event's settings. The key can create and delete questions, so it
   stays on this machine and is never stored in the file.
2. Write your polls and quizzes in the sidebar.
3. On the **On slides** tab, press **Put the code on this slide**. It inserts a
   picture on the slide you have open, so the room knows how to join.
4. On the same tab, create the slide link once. It is read-only, so it is saved
   into the presentation and travels with it.
5. Insert **Claper on a slide** wherever you want a live answer and pick what
   the block shows. It finds the link by itself.

## PowerPoint limitations

- PowerPoint draws a frame and a soft shadow along the top edge of every content
  add-in. Fill, Outline and Effects are greyed out on it, and neither the
  manifest nor CSS can change it. Content that does not need to be live looks
  better as a picture, which is why the joining code is one.
- Only a content add-in renders live during a slideshow, and a manifest carries
  exactly one `xsi:type`, so the block and the sidebar cannot be one add-in. The
  sidebar alone is enough to write questions and put the joining code on a
  slide; live results need the slide add-in.
- When a slide holding a block is duplicated in PowerPoint for the web, the copy
  keeps the original's instance id (office-js#2765) and the two can read each
  other's choice. Insert a second block instead of copying one.
- Handing the link to the blocks uses a presentation tag, which needs
  PowerPointApi 1.3. Where that is missing the sidebar says so and the link has
  to be pasted into each block once.

## What ends up inside the .pptx

The slide link and each block's choice are stored in the presentation file.
Anyone who unzips a .pptx can read them, so a deck you send out carries its
slide link in the clear. This is why the link is read-only and the sidebar key
stays on your machine.

## What the two keys can do

| | Sidebar key | Slide link |
|---|---|---|
| Create, edit and delete questions | yes | no |
| Read the presenter view | no | yes |
| Belongs in the .pptx | **no** | yes |

Both are revoked from the event's settings and stop working when the event
ends.
