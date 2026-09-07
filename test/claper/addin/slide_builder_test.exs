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

    slide_parts =
      for n <- 1..slides, into: %{} do
        {"ppt/slides/slide#{n}.xml", "<p:sld/>"}
      end

    rel_parts =
      for n <- 1..slides, into: %{} do
        webext =
          if n == slides do
            ~s(<Relationship Id="rId2" Type="http://schemas.microsoft.com/office/2011/relationships/webextension" Target="../webextensions/webextension1.xml"/>)
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
        ~s(<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>#{overrides}<Override PartName="/ppt/webextensions/taskpanes.xml" ContentType="application/vnd.ms-office.webextensiontaskpanes+xml"/></Types>),
      "_rels/.rels" =>
        ~s(<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/><Relationship Id="rId1" Type="http://schemas.microsoft.com/office/2011/relationships/webextensiontaskpanes" Target="ppt/webextensions/taskpanes.xml"/></Relationships>),
      "ppt/presentation.xml" =>
        ~s(<?xml version="1.0"?><p:presentation xmlns:p="p" xmlns:r="r"><p:sldIdLst>#{sld_ids}</p:sldIdLst></p:presentation>),
      "ppt/_rels/presentation.xml.rels" =>
        ~s(<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{slide_rels}<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/tags" Target="tags/tag1.xml"/></Relationships>),
      "ppt/tags/tag1.xml" => "<p:tagLst/>",
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

    test "the source document's own tags and task pane do not travel" do
      {:ok, built} = SlideBuilder.one_slide(deck(), %{"kind" => "poll", "id" => 7})
      kept = parts(built)

      refute Map.has_key?(kept, "ppt/tags/tag1.xml")
      refute Map.has_key?(kept, "ppt/webextensions/taskpanes.xml")
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
