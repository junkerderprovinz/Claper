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
      "[Content_Types].xml" =>
        ~s(<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">#{overrides}<Override PartName="/ppt/webextensions/taskpanes.xml" ContentType="application/vnd.ms-office.webextensiontaskpanes+xml"/></Types>),
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
      "ppt/webextensions/taskpanes.xml" => "<wetp:taskpanes/>",
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
