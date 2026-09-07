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

  @doc """
  The same, but built on the slide the author is standing on rather than on the
  one the block was copied from.

  `onto` is a position in the deck, counted from one in the order the slides are
  shown. What comes back is that slide with a Claper block added, which the
  add-in puts back in its place: the effect for the author is a block appearing
  on the slide they had open, keeping everything already on it.

  The block cannot simply be pasted across. It is an `mc:AlternateContent`
  carrying both the live object and a picture to fall back on, and both halves
  point at relationships by id. Those ids mean something different in the target
  slide, so they are renumbered on the way over, and so are the shape ids, which
  have to be unique within a slide.
  """
  def onto_slide(pptx, choice, onto)
      when is_binary(pptx) and is_map(choice) and is_integer(onto) do
    with {:ok, parts, order} <- unzip(pptx),
         {:ok, source, webext} <- find_block(parts),
         {:ok, target} <- slide_at(parts, onto) do
      if target == source do
        # It already carries one. Copying a second block onto it would give the
        # author two objects showing the same thing.
        parts |> patch_settings(webext, choice) |> keep_only(target, webext) |> zip(order)
      else
        with {:ok, moved} <- copy_block(parts, source, target) do
          moved |> patch_settings(webext, choice) |> keep_only(target, webext) |> zip(order)
        end
      end
    end
  end

  # The slide shown in a given place, which is not the same as the file called
  # slideN.xml: the running order lives in presentation.xml as a list of
  # relationship ids, and deleting or reordering slides in PowerPoint leaves the
  # file names where they were.
  defp slide_at(parts, position) when position >= 1 do
    rels = parts["ppt/_rels/presentation.xml.rels"] || ""

    targets =
      rels
      |> SweetXml.xpath(~x"//*[local-name()='Relationship']"l,
        id: ~x"./@Id"s,
        type: ~x"./@Type"s,
        target: ~x"./@Target"s
      )
      |> Enum.filter(&String.ends_with?(&1.type, "/slide"))
      |> Map.new(&{&1.id, "ppt/" <> String.trim_leading(&1.target, "/ppt/")})

    # Read with a pattern rather than an xpath: a `p:sldId` carries both its own
    # `id` and the relationship's `r:id`, and `local-name()`, which is what a
    # default namespace forces, cannot tell those two apart.
    order =
      Regex.scan(~r{<p:sldId [^>]*r:id="(rId\d+)"}, parts["ppt/presentation.xml"] || "")
      |> Enum.map(&Enum.at(&1, 1))

    case order |> Enum.at(position - 1) |> then(&Map.get(targets, &1)) do
      nil -> {:error, :no_such_slide}
      slide -> {:ok, slide}
    end
  end

  defp slide_at(_parts, _position), do: {:error, :no_such_slide}

  defp copy_block(parts, source, target) do
    with {:ok, block} <- block_markup(parts[source]) do
      source_rels = parts[rels_path(source)] || ""
      target_rels = parts[rels_path(target)] || ""

      {block, target_rels} = carry_relationships(block, source_rels, target_rels)
      block = renumber_shapes(block, parts[target])

      {:ok,
       parts
       |> Map.put(target, insert_into_tree(parts[target], block))
       |> Map.put(rels_path(target), target_rels)}
    end
  end

  # The whole element the reference sits in, not just the reference: an
  # AlternateContent when PowerPoint wrote one, the bare graphic frame when it
  # did not. Found by walking out from the reference and counting nesting, since
  # a regular expression cannot match a balanced pair.
  defp block_markup(slide_xml) when is_binary(slide_xml) do
    case :binary.match(slide_xml, "<we:webextensionref") do
      :nomatch ->
        {:error, :no_block}

      {at, _} ->
        Enum.find_value(
          [
            {"mc:AlternateContent", "<mc:AlternateContent"},
            {"p:graphicFrame", "<p:graphicFrame"}
          ],
          {:error, :no_block},
          fn {name, open} ->
            with start when is_integer(start) <- last_index(slide_xml, open, at),
                 stop when is_integer(stop) <- closing(slide_xml, name, start) do
              {:ok, binary_part(slide_xml, start, stop - start)}
            else
              _ -> nil
            end
          end
        )
    end
  end

  defp block_markup(_), do: {:error, :no_block}

  # The last occurrence of `needle` that starts before `before`.
  defp last_index(haystack, needle, before) do
    :binary.matches(haystack, needle)
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&(&1 <= before))
    |> List.last()
  end

  # Where the element opened at `start` ends, counting nested elements of the
  # same name so a graphic frame inside a fallback does not close the outer one.
  defp closing(xml, name, start) do
    opens = :binary.matches(xml, "<" <> name) |> Enum.map(&{elem(&1, 0), :open})
    closes = :binary.matches(xml, "</" <> name <> ">") |> Enum.map(&{elem(&1, 0), :close})

    (opens ++ closes)
    |> Enum.sort()
    |> Enum.filter(fn {at, _} -> at >= start end)
    |> Enum.reduce_while(0, fn
      {_at, :open}, depth ->
        {:cont, depth + 1}

      {at, :close}, 1 ->
        {:halt, at + byte_size("</" <> name <> ">")}

      {_at, :close}, depth ->
        {:cont, depth - 1}
    end)
    |> case do
      stop when is_integer(stop) and stop > start -> stop
      _ -> nil
    end
  end

  # Every relationship the block names is copied into the target slide under an
  # id that is free there, and the block is rewritten to use the new ones. Both
  # halves matter: the live object points at the webextension, the fallback
  # picture at an image.
  defp carry_relationships(block, source_rels, target_rels) do
    wanted =
      Regex.scan(~r{r:(?:id|embed|link)="(rId\d+)"}, block)
      |> Enum.map(&Enum.at(&1, 1))
      |> Enum.uniq()

    known =
      Regex.scan(~r{<Relationship [^>]*Id="(rId\d+)"[^>]*/>}, source_rels)
      |> Map.new(fn [whole, id] -> {id, whole} end)

    {mapping, added, _next} =
      Enum.reduce(wanted, {%{}, [], free_rel_id(target_rels)}, fn old, {map, acc, next} ->
        case Map.get(known, old) do
          nil ->
            {map, acc, next}

          markup ->
            new = "rId#{next}"

            {Map.put(map, old, new),
             [String.replace(markup, ~s(Id="#{old}"), ~s(Id="#{new}")) | acc], next + 1}
        end
      end)

    rewritten =
      Enum.reduce(mapping, block, fn {old, new}, acc ->
        Regex.replace(~r{(r:(?:id|embed|link)=")#{old}(")}, acc, "\\1#{new}\\2")
      end)

    {rewritten,
     String.replace(
       target_rels,
       "</Relationships>",
       Enum.join(Enum.reverse(added)) <> "</Relationships>"
     )}
  end

  defp free_rel_id(rels) do
    Regex.scan(~r{Id="rId(\d+)"}, rels)
    |> Enum.map(fn [_, n] -> String.to_integer(n) end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  # Shape ids have to be unique inside a slide, and the block brings the ids it
  # had on the slide it came from. Both copies in an AlternateContent carry the
  # same one on purpose, so they are renumbered together rather than one by one.
  defp renumber_shapes(block, target_xml) do
    highest =
      Regex.scan(~r{<p:cNvPr id="(\d+)"}, target_xml || "")
      |> Enum.map(fn [_, n] -> String.to_integer(n) end)
      |> Enum.max(fn -> 1 end)

    old =
      Regex.scan(~r{<p:cNvPr id="(\d+)"}, block)
      |> Enum.map(fn [_, n] -> String.to_integer(n) end)
      |> Enum.uniq()

    # Through a placeholder, because a new id can be an old one further down the
    # list: renaming 4 to 7 and then 7 to 8 in one pass renames both to 8.
    numbered = Enum.with_index(old, highest + 1)

    staged =
      Enum.reduce(numbered, block, fn {was, now}, acc ->
        Regex.replace(~r{(<p:cNvPr id=")#{was}(")}, acc, "\\1@@#{now}@@\\2")
      end)

    Enum.reduce(numbered, staged, fn {_was, now}, acc ->
      String.replace(acc, ~s(id="@@#{now}@@"), ~s(id="#{now}"))
    end)
  end

  # Last in the shape tree, which is what PowerPoint does when something is
  # added to a slide: it lands on top of what is already there.
  defp insert_into_tree(slide_xml, block) do
    String.replace(slide_xml, "</p:spTree>", block <> "</p:spTree>", global: false)
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

  # One of the three is set and the other two are cleared, always. A block
  # carries whichever it was last pointed at, so leaving the old key in place
  # would put two interactions in the link and let the view pick.
  defp apply_choice(settings, %{"kind" => kind, "id" => id})
       when kind in ~w(poll quiz form),
       do: settings |> Map.put("show", "interaction") |> pick(kind, id)

  defp apply_choice(settings, %{"kind" => show}) when show in ~w(join messages),
    do: settings |> Map.put("show", show) |> pick(nil, nil)

  defp apply_choice(settings, _), do: settings

  defp pick(settings, kind, id) do
    Enum.reduce(~w(poll quiz form), settings, fn key, acc ->
      Map.put(acc, key, if(key == kind, do: id, else: nil))
    end)
  end

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

  # Only the other slides go, and nothing else.
  #
  # An earlier version also threw out the task pane part, the other
  # webextensions and the presentation's tags, on the reasoning that they
  # describe the source document rather than the slide. PowerPoint refused every
  # file that did. The reason is in `ppt/presentation.xml`, which carries
  # `<p:custDataLst><p:tags r:id="rId3"/></p:custDataLst>`: removing the tags
  # part and its relationship leaves that pointer aimed at nothing, and a
  # relationship id with no relationship makes the package corrupt.
  #
  # Rather than chase every place a part might be named, nothing is removed that
  # does not have to be. Only slides are inserted from this file, so whatever
  # else it carries is never looked at, and the file exists for a fraction of a
  # second on the way into PowerPoint.
  defp keep_only(parts, slide, _webext) do
    other_slides =
      parts
      |> Map.keys()
      |> Enum.filter(&Regex.match?(~r{^ppt/slides/slide\d+\.xml$}, &1))
      |> Enum.reject(&(&1 == slide))

    drop = Enum.flat_map(other_slides, &[&1, rels_path(&1)])
    kept = Map.drop(parts, drop)

    kept
    |> Map.put("[Content_Types].xml", drop_overrides(kept["[Content_Types].xml"], drop))
    |> single_slide_presentation(slide)
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
        ~r{<Relationship [^>]*Type="[^"]*/slide"[^>]*/>},
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
