defmodule Claper.Addin.SlideBuilder do
  @moduledoc """
  Builds a one-slide presentation that PowerPoint can insert, from a deck that
  already contains a Claper block, with the block pointed at another interaction.

  The existing block is used as the template because its add-in reference
  depends on how the add-in was installed on that machine. Only the block's
  settings property is changed.
  """

  import SweetXml, only: [sigil_x: 2]

  @manifest Path.expand(Path.join(__DIR__, "../../../priv/addin_manifests/claper-on-a-slide.xml"))
  @external_resource @manifest

  @addin_id Regex.run(~r{<Id>([^<]+)</Id>}, File.read!(@manifest)) |> Enum.at(1) |> String.trim()

  # The add-in stores a JSON string through `settings.set`, so the property holds
  # JSON encoded twice.
  @settings_key "claper.slide"

  @webextension_rel "http://schemas.microsoft.com/office/2011/relationships/webextension"

  @doc """
  Returns the add-in id of the slide block, read from its manifest.
  """
  def addin_id, do: @addin_id

  @doc """
  Builds a one-slide presentation from `pptx`, showing what `choice` names.

  `choice` is `%{"kind" => "poll" | "quiz" | "form", "id" => integer}` or
  `%{"kind" => "join" | "messages"}`.

  Returns `{:ok, binary}`, or `{:error, :no_block}` when the presentation has no
  Claper block yet.
  """
  def one_slide(pptx, choice) when is_binary(pptx) and is_map(choice) do
    with {:ok, parts, order} <- unzip(pptx),
         {:ok, slide, webext} <- find_block(parts) do
      parts
      |> patch_settings(webext, choice)
      |> keep_only(slide)
      |> zip(order)
    end
  end

  @doc """
  Like `one_slide/2`, but adds the block to the slide at position `onto`,
  counted from one in show order, keeping what is already on it.
  """
  def onto_slide(pptx, choice, onto)
      when is_binary(pptx) and is_map(choice) and is_integer(onto) do
    with {:ok, parts, order} <- unzip(pptx),
         {:ok, source, webext} <- find_block(parts),
         {:ok, target} <- slide_at(parts, onto),
         {:ok, parts} <- block_on(parts, source, target) do
      parts |> patch_settings(webext, choice) |> keep_only(target) |> zip(order)
    end
  end

  defp block_on(parts, slide, slide), do: {:ok, parts}
  defp block_on(parts, source, target), do: copy_block(parts, source, target)

  # Show order comes from presentation.xml; slideN.xml file names do not follow
  # it once slides are moved or deleted.
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

    # `local-name()` cannot tell `id` from `r:id` on a `p:sldId`, so no xpath here.
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
          &enclosing(slide_xml, at, &1)
        )
    end
  end

  defp block_markup(_), do: {:error, :no_block}

  defp enclosing(slide_xml, at, {name, open}) do
    with start when is_integer(start) <- last_index(slide_xml, open, at),
         stop when is_integer(stop) <- closing(slide_xml, name, start) do
      {:ok, binary_part(slide_xml, start, stop - start)}
    else
      _ -> nil
    end
  end

  defp last_index(haystack, needle, before) do
    :binary.matches(haystack, needle)
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&(&1 <= before))
    |> List.last()
  end

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

  # Relationship ids are local to a slide, so the block's relationships get free
  # ids in the target slide.
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

  # Shape ids must be unique within a slide. Both halves of an AlternateContent
  # share one id, so each distinct id is mapped once.
  defp renumber_shapes(block, target_xml) do
    highest =
      Regex.scan(~r{<p:cNvPr id="(\d+)"}, target_xml || "")
      |> Enum.map(fn [_, n] -> String.to_integer(n) end)
      |> Enum.max(fn -> 1 end)

    old =
      Regex.scan(~r{<p:cNvPr id="(\d+)"}, block)
      |> Enum.map(fn [_, n] -> String.to_integer(n) end)
      |> Enum.uniq()

    # Two passes, since a new id can equal an old one later in the list.
    numbered = Enum.with_index(old, highest + 1)

    staged =
      Enum.reduce(numbered, block, fn {was, now}, acc ->
        Regex.replace(~r{(<p:cNvPr id=")#{was}(")}, acc, "\\1@@#{now}@@\\2")
      end)

    Enum.reduce(numbered, staged, fn {_was, now}, acc ->
      String.replace(acc, ~s(id="@@#{now}@@"), ~s(id="#{now}"))
    end)
  end

  defp insert_into_tree(slide_xml, block) do
    String.replace(slide_xml, "</p:spTree>", block <> "</p:spTree>", global: false)
  end

  # Keeps the original part order, since PowerPoint asks to repair a package
  # whose parts were reordered.
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
    # PowerPoint rejects the package unless the content types part comes first.
    names =
      [@content_types | Enum.reject(order, &(&1 == @content_types))]
      |> Enum.filter(&Map.has_key?(parts, &1))

    files = Enum.map(names, fn name -> {String.to_charlist(name), parts[name]} end)

    case :zip.create(~c"slide.pptx", files, [:memory]) do
      {:ok, {_name, binary}} -> {:ok, binary}
      _ -> {:error, :could_not_build}
    end
  end

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

  # A plain `//Relationship` matches nothing in the default namespace.
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

  # `Path.expand/2` would add a drive letter on Windows, so package paths are
  # resolved by hand.
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

  # The other interaction keys are cleared so a block never names two.
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

  # Removes only the other slides. Other parts can be referenced from
  # presentation.xml (tags, for one), and a dangling reference corrupts the
  # package.
  defp keep_only(parts, slide) do
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

  # The slide list and the relationships must lose the same entries, or
  # PowerPoint rejects the file.
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
      Regex.replace(
        ~r{<p:sldIdLst>.*?</p:sldIdLst>}s,
        parts["ppt/presentation.xml"],
        &keep_slide_id(&1, keep_id)
      )

    parts
    |> Map.put("ppt/_rels/presentation.xml.rels", trimmed_rels)
    |> Map.put("ppt/presentation.xml", presentation)
  end

  defp keep_slide_id(list, keep_id) do
    Regex.replace(~r{<p:sldId [^>]*/>}, list, fn entry ->
      if String.contains?(entry, ~s(r:id="#{keep_id}")), do: entry, else: ""
    end)
  end
end
