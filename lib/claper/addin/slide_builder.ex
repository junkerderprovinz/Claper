defmodule Claper.Addin.SlideBuilder do
  @moduledoc """
  Turns the presentation somebody is working in into a one-slide file that
  PowerPoint can insert, with the block on it pointed at a different question.

  The author's own deck is the template, and that is the whole idea rather than
  a convenience. A slide that already carries a Claper block records **how this
  machine reaches the add-in**: the reference names a store, and in a sideloaded
  install that store is a network path on the presenter's own computer
  (`storeType="Filesystem"`), while a centrally deployed or store-installed
  add-in records something else entirely. A template shipped with Claper would
  therefore be correct for exactly one way of installing and quietly broken for
  the others. Copying a slide out of the open document cannot be wrong that way.

  What is changed is one string: the block's own settings, which Office keeps in
  the webextension part as a property. Everything else is carried over
  untouched, so the copy resolves exactly as its original does.
  """

  import SweetXml, only: [sigil_x: 2]

  @manifest Path.expand(Path.join(__DIR__, "../../../priv/addin_manifests/claper-on-a-slide.xml"))
  @external_resource @manifest

  # The add-in the block on a slide belongs to. Taken from the manifest so the
  # two cannot drift: it is the same id PowerPoint writes into the document.
  @addin_id Regex.run(~r{<Id>([^<]+)</Id>}, File.read!(@manifest)) |> Enum.at(1) |> String.trim()

  # Office stores what `settings.set` was given, and it was given a JSON string,
  # so the property holds JSON of JSON.
  @settings_key "claper.slide"

  @webextension_rel "http://schemas.microsoft.com/office/2011/relationships/webextension"

  @doc """
  The add-in id this module looks for. Public so a test can prove it is the same
  one the manifest hands out rather than a second copy of it.
  """
  def addin_id, do: @addin_id

  @doc """
  Builds a one-slide presentation from `pptx`, showing what `choice` names.

  `choice` is `%{"kind" => "poll" | "quiz", "id" => integer}`.

  Returns `{:ok, binary}`, or `{:error, :no_block}` when the presentation has no
  Claper block yet, which is the one failure worth explaining to the author
  rather than reporting as a fault.
  """
  def one_slide(pptx, choice) when is_binary(pptx) and is_map(choice) do
    with {:ok, parts, order} <- unzip(pptx),
         {:ok, slide, webext} <- find_block(parts) do
      parts
      |> patch_settings(webext, choice)
      |> keep_only(slide, webext)
      |> zip(order)
    end
  end

  # The order the parts came in is kept, because a package is not just a bag of
  # files. Rebuilt out of a map it comes back in whatever order the map felt
  # like, and PowerPoint then offers to repair the file.
  defp unzip(pptx) do
    case :zip.unzip(pptx, [:memory]) do
      {:ok, files} ->
        named = Enum.map(files, fn {name, data} -> {List.to_string(name), data} end)
        {:ok, Map.new(named), Enum.map(named, &elem(&1, 0))}

      _ ->
        {:error, :not_a_presentation}
    end
  end

  @content_types "[Content_Types].xml"

  defp zip(parts, order) do
    # The content types part first, which is what an OPC reader looks for before
    # it knows what anything else is. Measured: with it at position 35 of 40,
    # PowerPoint refused the file and offered to repair it.
    names =
      [@content_types | Enum.reject(order, &(&1 == @content_types))]
      |> Enum.filter(&Map.has_key?(parts, &1))

    files = Enum.map(names, fn name -> {String.to_charlist(name), parts[name]} end)

    case :zip.create(~c"slide.pptx", files, [:memory]) do
      {:ok, {_name, binary}} -> {:ok, binary}
      _ -> {:error, :could_not_build}
    end
  end

  # The first slide whose own relationships lead to a webextension that names
  # our add-in. First rather than best: they are all equally valid templates,
  # since what is copied is the reference, not the question.
  defp find_block(parts) do
    parts
    |> Map.keys()
    |> Enum.filter(&Regex.match?(~r{^ppt/slides/slide\d+\.xml$}, &1))
    |> Enum.sort()
    |> Enum.find_value({:error, :no_block}, fn slide ->
      case block_of(parts, slide) do
        nil -> nil
        webext -> {:ok, slide, webext}
      end
    end)
  end

  defp block_of(parts, slide) do
    rels = rels_path(slide)

    with data when is_binary(data) <- parts[rels],
         targets <- webextension_targets(data) do
      Enum.find(targets, fn target ->
        part = resolve(slide, target)
        ours?(parts[part])
      end)
      |> case do
        nil -> nil
        target -> resolve(slide, target)
      end
    else
      _ -> nil
    end
  end

  # `local-name()` throughout: a relationships part puts its elements in a
  # default namespace, and a plain `//Relationship` matches nothing there.
  defp webextension_targets(rels_xml) do
    rels_xml
    |> SweetXml.xpath(~x"//*[local-name()='Relationship']"l,
      target: ~x"./@Target"s,
      type: ~x"./@Type"s
    )
    |> Enum.filter(&(&1.type == @webextension_rel))
    |> Enum.map(& &1.target)
  end

  defp ours?(nil), do: false

  defp ours?(webextension_xml) do
    id = SweetXml.xpath(webextension_xml, ~x"//*[local-name()='reference']/@id"s)
    String.downcase(id) == String.downcase(@addin_id)
  end

  # "../webextensions/webextension2.xml" seen from "ppt/slides/slide1.xml".
  #
  # Walked by hand rather than through `Path.expand/2`, which resolves against
  # the filesystem: on Windows it answers "d:/ppt/webextensions/..." and nothing
  # matches. A path inside a package belongs to the package, not to a disk.
  defp resolve(from, target) do
    base = from |> dirname() |> split()

    target
    |> split()
    |> Enum.reduce(base, fn
      ".", acc -> acc
      "..", acc -> Enum.drop(acc, -1)
      segment, acc -> acc ++ [segment]
    end)
    |> Enum.join("/")
  end

  defp split(path), do: path |> String.split("/") |> Enum.reject(&(&1 == ""))

  defp dirname(path) do
    path |> split() |> Enum.drop(-1) |> Enum.join("/")
  end

  defp basename(path), do: path |> split() |> List.last()

  defp rels_path(part), do: Enum.join([dirname(part), "_rels", basename(part) <> ".rels"], "/")

  # Only the block's own settings change. They are read back out first so the
  # look the author chose on the original slide is carried over rather than
  # reset to whatever this module would have picked.
  defp patch_settings(parts, webext, choice) do
    xml = parts[webext]

    updated =
      Regex.replace(
        ~r{(<we:property name="#{Regex.escape(@settings_key)}" value=")([^"]*)(")},
        xml,
        fn _whole, before, value, after_ ->
          before <> encode_settings(apply_choice(decode_settings(value), choice)) <> after_
        end
      )

    Map.put(parts, webext, updated)
  end

  defp decode_settings(escaped) do
    with decoded when is_binary(decoded) <- unescape(escaped),
         {:ok, inner} when is_binary(inner) <- Jason.decode(decoded),
         {:ok, settings} when is_map(settings) <- Jason.decode(inner) do
      settings
    else
      _ -> %{}
    end
  end

  defp encode_settings(settings) do
    settings
    |> Jason.encode!()
    |> Jason.encode!()
    |> escape()
  end

  defp apply_choice(settings, %{"kind" => "quiz", "id" => id}),
    do: settings |> Map.put("show", "interaction") |> Map.put("quiz", id) |> Map.put("poll", nil)

  defp apply_choice(settings, %{"kind" => "poll", "id" => id}),
    do: settings |> Map.put("show", "interaction") |> Map.put("poll", id) |> Map.put("quiz", nil)

  defp apply_choice(settings, %{"kind" => show}) when show in ~w(join messages),
    do: settings |> Map.put("show", show) |> Map.put("poll", nil) |> Map.put("quiz", nil)

  defp apply_choice(settings, _), do: settings

  defp unescape(value) do
    value
    |> String.replace("&quot;", "\"")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
  end

  defp escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  # Everything the package needs, and nothing that belongs to the rest of the
  # deck. The other slides go because only one is being inserted; the task pane
  # part and the presentation's tags go because they describe the source
  # document rather than the slide, and the target document has its own.
  defp keep_only(parts, slide, webext) do
    other_slides =
      parts
      |> Map.keys()
      |> Enum.filter(&Regex.match?(~r{^ppt/slides/slide\d+\.xml$}, &1))
      |> Enum.reject(&(&1 == slide))

    other_webextensions =
      parts
      |> Map.keys()
      |> Enum.filter(&Regex.match?(~r{^ppt/webextensions/webextension\d+\.xml$}, &1))
      |> Enum.reject(&(&1 == webext))

    drop =
      other_slides
      |> Enum.flat_map(&[&1, rels_path(&1)])
      |> Kernel.++(Enum.flat_map(other_webextensions, &[&1, rels_path(&1)]))
      |> Kernel.++([
        "ppt/webextensions/taskpanes.xml",
        "ppt/webextensions/_rels/taskpanes.xml.rels"
      ])
      |> Kernel.++(Enum.filter(Map.keys(parts), &String.starts_with?(&1, "ppt/tags/")))

    kept = Map.drop(parts, drop)

    kept
    |> Map.put("[Content_Types].xml", drop_overrides(kept["[Content_Types].xml"], drop))
    |> drop_root_relationships(drop)
    |> single_slide_presentation(slide)
  end

  # The task pane part is referenced from the package's own root relationships,
  # not from the presentation's, so removing the part alone leaves a pointer to
  # something that is not there. Measured on a real file: everything else in
  # that part resolved, this one did not.
  defp drop_root_relationships(parts, dropped) do
    Map.update!(parts, "_rels/.rels", fn rels ->
      Enum.reduce(dropped, rels, fn part, acc ->
        Regex.replace(~r{<Relationship [^>]*Target="#{Regex.escape(part)}"[^>]*/>}, acc, "")
      end)
    end)
  end

  defp drop_overrides(content_types, dropped) do
    Enum.reduce(dropped, content_types, fn part, acc ->
      Regex.replace(~r{<Override PartName="/#{Regex.escape(part)}"[^>]*/>}, acc, "")
    end)
  end

  # The presentation part lists its slides by relationship id, so both the list
  # and the relationships have to lose the same entries or PowerPoint refuses
  # the file.
  defp single_slide_presentation(parts, slide) do
    rels = parts["ppt/_rels/presentation.xml.rels"]
    target = String.trim_leading(slide, "ppt/")

    keep_id =
      rels
      |> SweetXml.xpath(~x"//*[local-name()='Relationship']"l,
        id: ~x"./@Id"s,
        target: ~x"./@Target"s
      )
      |> Enum.find(%{}, &(&1.target == target))
      |> Map.get(:id, "")

    trimmed_rels =
      Regex.replace(
        ~r{<Relationship [^>]*Type="[^"]*/(slide|tags)"[^>]*/>},
        rels,
        fn whole ->
          if String.contains?(whole, ~s(Id="#{keep_id}")), do: whole, else: ""
        end
      )

    presentation =
      Regex.replace(~r{<p:sldIdLst>.*?</p:sldIdLst>}s, parts["ppt/presentation.xml"], fn list ->
        Regex.replace(~r{<p:sldId [^>]*/>}, list, fn entry ->
          if String.contains?(entry, ~s(r:id="#{keep_id}")), do: entry, else: ""
        end)
      end)

    parts
    |> Map.put("ppt/_rels/presentation.xml.rels", trimmed_rels)
    |> Map.put("ppt/presentation.xml", presentation)
  end
end
