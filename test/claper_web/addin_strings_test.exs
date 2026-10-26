defmodule ClaperWeb.AddinStringsTest do
  use ExUnit.Case, async: true

  alias ClaperWeb.AddinStrings

  # The add-in pages are static files, so a sentence on them is translated only
  # if it appears verbatim as a key in AddinStrings.
  @pages ["priv/static/addin/sidebar.html", "priv/static/addin/slide.html"]

  # Product names, numerals and separators stay the same in every language.
  @not_language ~w(Claper PowerPoint 1 2 3 4 · × …)

  # The page looks up whole text nodes, and a node can hold a sentence the
  # markup wraps across several lines.
  defp text_nodes({tag, _attrs, _children}) when tag in ["script", "style"], do: []
  defp text_nodes({_tag, _attrs, children}), do: Enum.flat_map(children, &text_nodes/1)
  defp text_nodes(text) when is_binary(text), do: [text]
  defp text_nodes(_other), do: []

  defp visible_text(path) do
    path
    |> File.read!()
    |> Floki.parse_document!()
    |> Enum.flat_map(&text_nodes/1)
    |> Enum.map(&(&1 |> String.replace(~r/\s+/, " ") |> String.trim()))
    |> Enum.reject(&(&1 == "" or &1 in @not_language))
    |> Enum.uniq()
  end

  describe "the dictionary against the pages" do
    test "every sentence the add-in shows has a key" do
      keys = AddinStrings.strings() |> Map.keys() |> MapSet.new()

      missing =
        @pages
        |> Enum.flat_map(fn path -> Enum.map(visible_text(path), &{path, &1}) end)
        |> Enum.reject(fn {_path, text} -> MapSet.member?(keys, text) end)

      assert missing == [],
             "These are shown to the reader but have no entry in AddinStrings, so they " <>
               "stay English in every language:\n" <>
               Enum.map_join(missing, "\n", fn {p, t} -> "  #{p}: #{inspect(t)}" end)
    end

    test "every language has the same keys" do
      all = AddinStrings.all()
      english = all["en"] |> Map.keys() |> MapSet.new()

      for {locale, map} <- all do
        assert MapSet.new(Map.keys(map)) == english,
               "#{locale} does not carry the same keys as English"
      end
    end

    test "no translation falls back to English wholesale" do
      all = AddinStrings.all()

      for locale <- Map.keys(all), locale != "en" do
        same = Enum.count(all[locale], fn {key, value} -> key == value end)
        total = map_size(all[locale])

        assert same < div(total, 2),
               "#{locale} leaves #{same} of #{total} strings at their English text"
      end
    end
  end

  describe "what the page looks up" do
    # The page collapses whitespace in a text node before the lookup.
    test "keys have no line breaks or repeated spaces" do
      for {key, _} <- AddinStrings.strings() do
        assert key == String.replace(key, ~r/\s+/, " ") |> String.trim(),
               "key #{inspect(key)} would never match a collapsed text node"
      end
    end
  end
end
