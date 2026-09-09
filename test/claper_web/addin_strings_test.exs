defmodule ClaperWeb.AddinStringsTest do
  use ExUnit.Case, async: true

  alias ClaperWeb.AddinStrings

  # The two add-in pages are static files. Nothing on them passes through
  # gettext, so the only thing standing between a sentence and a room that
  # cannot read it is whether that exact sentence is a key in this map. Nobody
  # notices a missing key: the page renders, in English, next to text that
  # turned. These tests are the thing that notices.
  @pages ["priv/static/addin/sidebar.html", "priv/static/addin/slide.html"]

  # Text that is deliberately not translated. A product name has nothing to
  # translate and a fuzzy match once turned "Claper" into "Applaus"; a numeral
  # is the same in every language this speaks and would only be a target for a
  # mistake. Punctuation and separators are markup, not language.
  @not_language ~w(Claper PowerPoint 1 2 3 4 · × …)

  # One entry per text node, not per line. The page looks a whole text node up,
  # and a node holds the sentence the markup wrapped across three lines. Joining
  # the nodes and splitting on newlines instead would test thirds of sentences
  # against a dictionary of whole ones and report every wrapped paragraph as
  # missing.
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
    |> Enum.reject(&(&1 == ""))
    |> Enum.reject(&(&1 in @not_language))
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

    test "every language answers with the same set of keys" do
      all = AddinStrings.all()
      english = all["en"] |> Map.keys() |> MapSet.new()

      for {locale, map} <- all do
        assert MapSet.new(Map.keys(map)) == english,
               "#{locale} does not carry the same keys as English"
      end
    end

    test "a translated language actually translates" do
      # Not a count of filled rows. A row filled by a fuzzy match is filled and
      # wrong, which is how "Points" came to read "Anpinnen" in German and
      # "Spin again" came to read "Log in" in all eight. What this asserts is
      # that the language differs from English at all, which is the cheapest
      # check that catches a locale silently falling back wholesale.
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
    test "the wrapped paragraphs match a key once whitespace is collapsed" do
      # The page collapses whitespace before looking a text node up, because the
      # markup wraps sentences across lines and the key does not. This asserts
      # the collapsed form is what the key actually is: a key carrying a line
      # break or a double space could never be hit.
      for {key, _} <- AddinStrings.strings() do
        assert key == String.replace(key, ~r/\s+/, " ") |> String.trim(),
               "key #{inspect(key)} would never match a collapsed text node"
      end
    end
  end
end
