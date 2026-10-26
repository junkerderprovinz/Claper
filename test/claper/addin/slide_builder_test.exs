defmodule Claper.Addin.SlideBuilderTest do
  use ExUnit.Case, async: true

  alias Claper.Addin.SlideBuilder

  # Built in code because a real presentation with a block also carries a local
  # add-in path and an embed link. The structure follows a file PowerPoint wrote.
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

    # PowerPoint writes the live object and a fallback picture inside an
    # AlternateContent, each half with a relationship of its own.
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
      |> Enum.map_join(fn n -> ~s(<p:sldId id="#{255 + n}" r:id="rId#{10 + n}"/>) end)

    slide_rels =
      1..slides
      |> Enum.map_join(fn n ->
        ~s(<Relationship Id="rId#{10 + n}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide#{n}.xml"/>)
      end)

    overrides =
      1..slides
      |> Enum.map_join(fn n ->
        ~s(<Override PartName="/ppt/slides/slide#{n}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>)
      end)

    base = %{
      # The defaults a real file carries, so the content type check tests the
      # module rather than a gap in this fixture.
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
      # Every slide points at a layout, and the checks below expect every
      # relationship to resolve.
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
      # Filler to push the package past 32 parts. Smaller Erlang maps keep their
      # keys sorted, which would put "[Content_Types].xml" first by chance.
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

  # PowerPoint offers to repair a package whose content types part is not the
  # first entry, although python-pptx opens such a file without complaint.
  test "the content types part comes first" do
    {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})

    {:ok, files} = :zip.unzip(built, [:memory])
    [first | _] = Enum.map(files, fn {name, _} -> List.to_string(name) end)

    assert first == "[Content_Types].xml"
  end

  test "every part in the package has a content type" do
    {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})
    kept = parts(built)

    types = kept["[Content_Types].xml"]
    defaults = Regex.scan(~r{Extension="([^"]+)"}, types) |> Enum.map(&Enum.at(&1, 1))
    overrides = Regex.scan(~r{PartName="/([^"]+)"}, types) |> Enum.map(&Enum.at(&1, 1))

    for name <- Map.keys(kept), name != "[Content_Types].xml" do
      extension = name |> String.split(".") |> List.last()

      assert name in overrides or extension in defaults,
             "#{name} has no content type"
    end
  end

  test "the add-in id matches the manifest" do
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

    test "keeps the block's style settings" do
      {:ok, built} = SlideBuilder.one_slide(deck(), %{"kind" => "poll", "id" => 7})

      assert %{"theme" => "dark", "panel" => "off", "radius" => "round", "shadow" => "on"} =
               settings_of(built)
    end

    # The reference tells PowerPoint how this machine reaches the add-in.
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

    # The package root references the task pane part, so removing a part can
    # leave a relationship pointing at nothing.
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

    # Only slides are inserted from this file, so other parts can stay, and
    # each part removed is another chance to leave a dangling relationship.
    test "nothing but the other slides is removed" do
      {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})
      kept = parts(built)

      assert Map.has_key?(kept, "ppt/tags/tag1.xml")
      assert Map.has_key?(kept, "ppt/webextensions/taskpanes.xml")
      refute Map.has_key?(kept, "ppt/slides/slide1.xml")
    end

    # presentation.xml names the tags part by relationship id in p:custDataLst,
    # and PowerPoint reports a file with a missing id as corrupt.
    test "every relationship id the presentation names exists" do
      {:ok, built} = SlideBuilder.one_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7})
      kept = parts(built)

      declared =
        Regex.scan(~r{Id="([^"]+)"}, kept["ppt/_rels/presentation.xml.rels"])
        |> Enum.map(&Enum.at(&1, 1))
        |> MapSet.new()

      for [_, used] <- Regex.scan(~r{r:id="([^"]+)"}, kept["ppt/presentation.xml"]) do
        assert MapSet.member?(declared, used),
               "presentation.xml uses #{used}, which its relationships do not declare"
      end
    end
  end

  # Each half of the block names a relationship id that means something else on
  # the target slide. The fixture puts the block on the last slide, so slide 1
  # of three has none.
  defp onto(position, choice \\ %{"kind" => "poll", "id" => 7}) do
    {:ok, built} = SlideBuilder.onto_slide(deck(slides: 3), choice, position)
    built
  end

  describe "putting the block on a slide that has none" do
    test "keeps the requested slide, not the one the block came from" do
      kept = parts(onto(1))

      assert Map.has_key?(kept, "ppt/slides/slide1.xml")
      refute Map.has_key?(kept, "ppt/slides/slide3.xml")
    end

    test "adds the block to that slide" do
      assert parts(onto(1))["ppt/slides/slide1.xml"] =~ "we:webextensionref"
    end

    test "keeps the slide's own shapes" do
      assert parts(onto(1))["ppt/slides/slide1.xml"] =~ ~s(name="Title")
    end

    # PowerPoint refuses a slide with duplicate shape ids, and the block brings
    # the id it had on its own slide.
    test "the copied shape does not take an id the slide already uses" do
      ids =
        Regex.scan(~r{<p:cNvPr id="(\d+)"}, parts(onto(1))["ppt/slides/slide1.xml"])
        |> Enum.map(&Enum.at(&1, 1))

      assert length(ids) == 3, "one own shape and both halves of the block"
      assert length(Enum.uniq(ids)) == 2, "both halves of the block keep one id between them"
      refute Enum.any?(ids, &String.contains?(&1, "@"))
    end

    # Without the image relationship the fallback picture points at nothing.
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

    test "points the block at the chosen question" do
      assert %{"quiz" => 9, "poll" => nil} = settings_of(onto(1, %{"kind" => "quiz", "id" => 9}))
    end

    test "the presentation is left listing one slide" do
      assert length(Regex.scan(~r{<p:sldId }, parts(onto(1))["ppt/presentation.xml"])) == 1
    end

    test "the content types part comes first" do
      {:ok, files} = :zip.unzip(onto(1), [:memory])
      [{first, _} | _] = files

      assert List.to_string(first) == "[Content_Types].xml"
    end

    test "a slide that already carries one does not get a second" do
      kept = parts(onto(3))

      assert length(Regex.scan(~r{we:webextensionref}, kept["ppt/slides/slide3.xml"])) == 1
    end

    test "a position outside the deck is refused" do
      assert SlideBuilder.onto_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7}, 9) ==
               {:error, :no_such_slide}

      assert SlideBuilder.onto_slide(deck(slides: 3), %{"kind" => "poll", "id" => 7}, 0) ==
               {:error, :no_such_slide}
    end
  end

  describe "when there is nothing to copy" do
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
