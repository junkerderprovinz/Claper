defmodule Claper.Addin.SlideBuilderTest do
  use ExUnit.Case, async: true

  alias Claper.Addin.SlideBuilder

  # Built here rather than committed. A real presentation carrying a block also
  # carries the path the machine that made it reaches the add-in through, and an
  # embed link: neither belongs in a repository. The shape is copied from a real
  # file, the contents are not.
  defp deck(opts \\ []) do
    addin = Keyword.get(opts, :addin_id, SlideBuilder.addin_id())
    slides = Keyword.get(opts, :slides, 2)

    settings =
      Keyword.get(
        opts,
        :settings,
        ~s({"link":"https://claper.test/embed/interaction/K","show":"interaction","poll":1,"quiz":null,"theme":"dark","panel":"off","radius":"round","shadow":"on"})
      )

    # The property holds JSON of JSON, XML escaped, which is what Office writes
    # when an add-in stores a string with settings.set.
    value =
      settings
      |> Jason.encode!()
      |> String.replace("&", "&amp;")
      |> String.replace("\"", "&quot;")

    # The shape PowerPoint really writes: the live object and a picture to fall
    # back on, wrapped in an AlternateContent, each half pointing at a
    # relationship of its own. Copying a block onto another slide has to carry
    # both, which is why the fixture carries both.
    block =
      ~s(<mc:AlternateContent xmlns:mc="mc"><mc:Choice Requires="wetp"><p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="4" name="Add-In 3"/></p:nvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/webextensions/webextension/2010/11"><we:webextensionref xmlns:we="we" xmlns:r="r" r:id="rId2"/></a:graphicData></a:graphic></p:graphicFrame></mc:Choice><mc:Fallback><p:pic><p:nvPicPr><p:cNvPr id="4" name="Add-In 3"/></p:nvPicPr><p:blipFill><a:blip r:embed="rId3"/></p:blipFill></p:pic></mc:Fallback></mc:AlternateContent>)

    slide_parts =
      for n <- 1..slides, into: %{} do
        # Something already on the slide, so a copied block has an existing
        # shape id to avoid rather than an empty tree to land in.
        own = ~s(<p:sp><p:nvSpPr><p:cNvPr id="#{n + 1}" name="Title"/></p:nvSpPr></p:sp>)
        shapes = if n == slides, do: own <> block, else: own

        {"ppt/slides/slide#{n}.xml",
         ~s(<?xml version="1.0"?><p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree>#{shapes}</p:spTree></p:cSld></p:sld>)}
      end

    rel_parts =
      for n <- 1..slides, into: %{} do
        webext =
          if n == slides do
            ~s(<Relationship Id="rId2" Type="http://schemas.microsoft.com/office/2011/relationships/webextension" Target="../webextensions/webextension1.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>)
          else
            ""
          end

        {"ppt/slides/_rels/slide#{n}.xml.rels",
         ~s(<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>#{webext}</Relationships>)}
      end

    sld_ids =
      1..slides
      |> Enum.map(fn n -> ~s(<p:sldId id="#{255 + n}" r:id="rId#{10 + n}"/>) end)
      |> Enum.join()

    slide_rels =
      1..slides
      |> Enum.map(fn n ->
        ~s(<Relationship Id="rId#{10 + n}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide#{n}.xml"/>)
      end)
      |> Enum.join()

    overrides =
      1..slides
      |> Enum.map(fn n ->
        ~s(<Override PartName="/ppt/slides/slide#{n}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>)
      end)
      |> Enum.join()

    base = %{
      # The defaults a real file carries, so the "everything has a content type"
      # check measures the module rather than a gap in this fixture.
      "[Content_Types].xml" =>
        ~s(<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>#{overrides}<Override PartName="/ppt/webextensions/taskpanes.xml" ContentType="application/vnd.ms-office.webextensiontaskpanes+xml"/></Types>),
      "_rels/.rels" =>
        ~s(<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/><Relationship Id="rId1" Type="http://schemas.microsoft.com/office/2011/relationships/webextensiontaskpanes" Target="ppt/webextensions/taskpanes.xml"/></Relationships>),
      "ppt/presentation.xml" =>
        ~s(<?xml version="1.0"?><p:presentation xmlns:p="p" xmlns:r="r"><p:sldIdLst>#{sld_ids}</p:sldIdLst><p:custDataLst><p:tags r:id="rId3"/></p:custDataLst></p:presentation>),
      "ppt/_rels/presentation.xml.rels" =>
        ~s(<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{slide_rels}<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/tags" Target="tags/tag1.xml"/></Relationships>),
      "ppt/tags/tag1.xml" => "<p:tagLst/>",
      # What the block's fallback picture points at.
      "ppt/media/image1.png" => "not really a png",
      # Every slide points at a layout, and the check below insists that every
      # pointer resolves, so the fixture has to carry one.
      "ppt/slideLayouts/slideLayout1.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout2.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout3.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout4.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout5.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout6.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout7.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout8.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout9.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout10.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout11.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout12.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout13.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout14.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout15.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout16.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout17.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout18.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout19.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout20.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout21.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout22.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout23.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout24.xml" => "<p:sldLayout/>",
      "ppt/slideLayouts/slideLayout25.xml" => "<p:sldLayout/>",
      "ppt/webextensions/taskpanes.xml" => "<wetp:taskpanes/>",
      # Filler, and it earns its place: below 32 entries Erlang keeps a map
      # sorted, and "[Content_Types].xml" then comes out first by luck even when
      # the code does not put it there. A real presentation has 40-odd parts and
      # a map that size hands them back in whatever order it likes, which is how
      # the defect reached PowerPoint in the first place.
      "ppt/theme/theme1.xml" => "<a:theme/>",
      "ppt/presProps.xml" => "<p:presentationPr/>",
      "ppt/viewProps.xml" => "<p:viewPr/>",
      "ppt/tableStyles.xml" => "<a:tblStyleLst/>",
      "docProps/app.xml" => "<Properties/>",
      "docProps/core.xml" => "<cp:coreProperties/>",
      "ppt/webextensions/webextension1.xml" =>
        ~s(<?xml version="1.0"?><we:webextension xmlns:we="http://schemas.microsoft.com/office/webextensions/webextension/2010/11" id="{X}"><we:reference id="#{addin}" version="1.0.0.0" store="\\\\MACHINE\\share" storeType="Filesystem"/><we:properties><we:property name="claper.slide" value="#{value}"/></we:properties></we:webextension>)
    }

    files =
      base
      |> Map.merge(slide_parts)
      |> Map.merge(rel_parts)
      |> Enum.map(fn {name, data} -> {String.to_charlist(name), data} end)

    {:ok, {_name, binary}} = :zip.create(~c"t.pptx", files, [:memory])
    binary
  end

  defp parts(binary) do
    {:ok, files} = :zip.unzip(binary, [:memory])
    Map.new(files, fn {n, d} -> {List.to_string(n), d} end)
  end

  defp settings_of(binary) do
    parts(binary)
    |> Map.fetch!("ppt/webextensions/webextension1.xml")
    |> then(&Regex.run(~r{name="claper.slide" value="([^"]*)"}, &1))
    |> Enum.at(1)
    |> String.replace("&quot;", "\"")
    |> String.replace("&amp;", "&")
    |> Jason.decode!()
    |> Jason.decode!()
  end

  # PowerPoint refused the first file this module produced and offered to repair
  # it. The package was otherwise sound: valid zip, every relationship resolved,
  # no orphaned content type. What was wrong was the ORDER. Rebuilt out of a map,
  # the content types part came out at position 35 of 40, and an OPC reader looks
  # for it before it knows what anything else in the package is.
  #
  # Worth stating plainly because it is why this is a test rather than a check
  # run once by hand: python-pptx opens the broken file without complaint, so a
  # library that reads the format does not stand in for the application that
  # wrote it.
  test "the content types part comes first, which is where a reader looks for it" do
    {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})

    {:ok, files} = :zip.unzip(built, [:memory])
    [first | _] = Enum.map(files, fn {name, _} -> List.to_string(name) end)

    assert first == "[Content_Types].xml"
  end

  # The direction the first round of checks missed. Orphaned content types were
  # checked, parts without one were not.
  test "every part in the package has a content type" do
    {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})
    kept = parts(built)

    types = kept["[Content_Types].xml"]
    defaults = Regex.scan(~r{Extension="([^"]+)"}, types) |> Enum.map(&Enum.at(&1, 1))
    overrides = Regex.scan(~r{PartName="/([^"]+)"}, types) |> Enum.map(&Enum.at(&1, 1))

    for name <- Map.keys(kept), name != "[Content_Types].xml" do
      extension = name |> String.split(".") |> List.last()

      assert name in overrides or extension in defaults,
             "#{name} has no content type, so a reader cannot tell what it is"
    end
  end

  test "the add-in id comes from the manifest, not from a second copy of it" do
    manifest = File.read!("priv/addin_manifests/claper-on-a-slide.xml")

    assert manifest =~ "<Id>#{SlideBuilder.addin_id()}</Id>"
  end

  describe "building a slide" do
    test "keeps one slide, the one carrying the block" do
      {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})
      kept = parts(built)

      assert Map.has_key?(kept, "ppt/slides/slide3.xml")
      refute Map.has_key?(kept, "ppt/slides/slide1.xml")
      refute Map.has_key?(kept, "ppt/slides/slide2.xml")
    end

    test "points the block at the chosen question" do
      {:ok, built} = SlideBuilder.one_slide(deck(), %{"kind" => "poll", "id" => 7})

      assert %{"poll" => 7, "quiz" => nil, "show" => "interaction"} = settings_of(built)
    end

    test "a quiz replaces the poll rather than sitting beside it" do
      {:ok, built} = SlideBuilder.one_slide(deck(), %{"kind" => "quiz", "id" => 9})

      assert %{"quiz" => 9, "poll" => nil} = settings_of(built)
    end

    # The author chose that look on the original slide, and copying the slide
    # should copy the slide.
    test "carries the look over untouched" do
      {:ok, built} = SlideBuilder.one_slide(deck(), %{"kind" => "poll", "id" => 7})

      assert %{"theme" => "dark", "panel" => "off", "radius" => "round", "shadow" => "on"} =
               settings_of(built)
    end

    # The reason the deck is the template at all: this reference says how this
    # machine reaches the add-in, and it must survive the copy exactly.
    test "leaves the add-in reference exactly as it was" do
      {:ok, built} = SlideBuilder.one_slide(deck(), %{"kind" => "poll", "id" => 7})
      webext = parts(built)["ppt/webextensions/webextension1.xml"]

      assert webext =~ ~s(storeType="Filesystem")
      assert webext =~ ~s(store="\\\\MACHINE\\share")
      assert webext =~ ~s(id="#{SlideBuilder.addin_id()}")
    end

    test "the presentation lists exactly the slide that is left" do
      {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})
      kept = parts(built)

      assert length(Regex.scan(~r{<p:sldId }, kept["ppt/presentation.xml"])) == 1

      assert length(
               Regex.scan(~r{/relationships/slide"}, kept["ppt/_rels/presentation.xml.rels"])
             ) == 1
    end

    # Measured on a real file: the task pane part is referenced from the
    # package's root relationships, so removing the part alone left a pointer to
    # nothing and the package was broken.
    test "leaves no relationship pointing at a part that is gone" do
      {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})
      kept = parts(built)

      for {name, data} <- kept, String.ends_with?(name, ".rels") do
        base = name |> String.replace("_rels/", "") |> Path.dirname()
        base = if base == ".", do: "", else: base

        for [_, target] <- Regex.scan(~r{Target="([^"]+)"}, data),
            not String.starts_with?(target, "http") do
          resolved = resolve(base, target)

          assert Map.has_key?(kept, resolved),
                 "#{name} points at #{target}, which is not in the package"
        end
      end
    end

    test "the content types list nothing that is gone" do
      {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})
      kept = parts(built)

      for [_, part] <- Regex.scan(~r{PartName="/([^"]+)"}, kept["[Content_Types].xml"]) do
        assert Map.has_key?(kept, part), "content types name #{part}, which is not in the package"
      end
    end

    # This asserted the opposite until PowerPoint refused every file. The tags
    # part and the task pane part belong to the source document rather than to
    # the slide, so throwing them out looked like tidying. It is not: only
    # slides are inserted from this file, so nothing else in it is ever looked
    # at, and every part removed is another chance to leave a pointer dangling.
    test "nothing but the other slides is removed" do
      {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})
      kept = parts(built)

      assert Map.has_key?(kept, "ppt/tags/tag1.xml")
      assert Map.has_key?(kept, "ppt/webextensions/taskpanes.xml")
      refute Map.has_key?(kept, "ppt/slides/slide1.xml")
    end

    # The defect itself, as a test. ppt/presentation.xml carries
    # <p:custDataLst><p:tags r:id="rId3"/></p:custDataLst>, and dropping the
    # tags relationship left that id pointing at nothing. PowerPoint called the
    # file corrupt and said no more than that.
    test "every relationship id the presentation names still exists" do
      {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})
      kept = parts(built)

      declared =
        Regex.scan(~r{Id="([^"]+)"}, kept["ppt/_rels/presentation.xml.rels"])
        |> Enum.map(&Enum.at(&1, 1))
        |> MapSet.new()

      for [_, used] <- Regex.scan(~r{r:id="([^"]+)"}, kept["ppt/presentation.xml"]) do
        assert MapSet.member?(declared, used),
               "presentation.xml uses #{used}, which its relationships no longer declare"
      end
    end
  end

  # "Put it on THIS slide" rather than on one of its own. The block cannot be
  # pasted across as it stands: it is an AlternateContent holding both the live
  # object and a picture to fall back on, and each half names a relationship by
  # an id that means something else on the target slide.
  # The fixture puts the block on the last slide, so slide 1 of three is a slide
  # that has to be given one.
  defp onto(position, choice \\ %{"kind" => "poll", "id" => 7}) do
    {:ok, built} = SlideBuilder.onto_slide(deck(slides: 3), choice, position)
    built
  end

  describe "putting the block on a slide that has none" do
    test "keeps the slide that was asked for, not the one the block came from" do
      kept = parts(onto(1))

      assert Map.has_key?(kept, "ppt/slides/slide1.xml")
      refute Map.has_key?(kept, "ppt/slides/slide3.xml")
    end

    test "the block ends up on it" do
      assert parts(onto(1))["ppt/slides/slide1.xml"] =~ "we:webextensionref"
    end

    test "what was already on the slide stays on it" do
      assert parts(onto(1))["ppt/slides/slide1.xml"] =~ ~s(name="Title")
    end

    # Two shapes with the same id is a slide PowerPoint refuses. The block
    # brings the id it had where it came from, and renaming ids one after
    # another can hand a shape an id another one is about to be given.
    test "the copied shape does not take an id the slide already uses" do
      ids =
        Regex.scan(~r{<p:cNvPr id="(\d+)"}, parts(onto(1))["ppt/slides/slide1.xml"])
        |> Enum.map(&Enum.at(&1, 1))

      assert length(ids) == 3, "one own shape and both halves of the block"
      assert length(Enum.uniq(ids)) == 2, "both halves of the block keep one id between them"
      refute Enum.any?(ids, &String.contains?(&1, "@"))
    end

    # Both halves, not just the live one: without the image the fallback points
    # at nothing, and a relationship id with no relationship is the corruption
    # that made PowerPoint offer to repair the file twice before.
    test "the relationships the block needs come with it" do
      kept = parts(onto(1))
      rels = kept["ppt/slides/_rels/slide1.xml.rels"]

      assert rels =~ "relationships/webextension"
      assert rels =~ "media/image1.png"

      for id <- Regex.scan(~r{r:(?:id|embed)="(rId\d+)"}, kept["ppt/slides/slide1.xml"]) do
        assert rels =~ ~s(Id="#{Enum.at(id, 1)}"),
               "#{Enum.at(id, 1)} is named on the slide but declared nowhere"
      end
    end

    test "no relationship id is handed out twice" do
      ids =
        Regex.scan(~r{Id="(rId\d+)"}, parts(onto(1))["ppt/slides/_rels/slide1.xml.rels"])
        |> Enum.map(&Enum.at(&1, 1))

      assert ids == Enum.uniq(ids)
    end

    test "the settings are pointed at the chosen question all the same" do
      assert %{"quiz" => 9, "poll" => nil} = settings_of(onto(1, %{"kind" => "quiz", "id" => 9}))
    end

    test "the presentation is left listing one slide" do
      assert length(Regex.scan(~r{<p:sldId }, parts(onto(1))["ppt/presentation.xml"])) == 1
    end

    test "the content types part still comes first" do
      {:ok, files} = :zip.unzip(onto(1), [:memory])
      [{first, _} | _] = files

      assert List.to_string(first) == "[Content_Types].xml"
    end

    # Asking for the slide the block is already on is not an error, it is a
    # request for that slide. Adding a second block would give the author two
    # objects showing the same question.
    test "a slide that already carries one does not get a second" do
      kept = parts(onto(3))

      assert length(Regex.scan(~r{we:webextensionref}, kept["ppt/slides/slide3.xml"])) == 1
    end

    test "a position the deck does not have is refused rather than guessed at" do
      assert SlideBuilder.onto_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7}, 9) ==
               {:error, :no_such_slide}

      assert SlideBuilder.onto_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7}, 0) ==
               {:error, :no_such_slide}
    end
  end

  describe "when there is nothing to copy" do
    # The one failure the author can act on, so it is told apart from a fault.
    test "a presentation with no Claper block says so" do
      assert {:error, :no_block} =
               SlideBuilder.one_slide(deck(addin_id: "11111111-2222-3333-4444-555555555555"), %{
                 "kind" => "poll",
                 "id" => 7
               })
    end

    test "something that is not a presentation says so" do
      assert {:error, :not_a_presentation} =
               SlideBuilder.one_slide("not a zip at all", %{"kind" => "poll", "id" => 7})
    end
  end

  defp resolve(base, target) do
    segments = if base == "", do: [], else: String.split(base, "/")

    target
    |> String.split("/")
    |> Enum.reduce(segments, fn
      "", acc -> acc
      ".", acc -> acc
      "..", acc -> Enum.drop(acc, -1)
      segment, acc -> acc ++ [segment]
    end)
    |> Enum.join("/")
  end
end
