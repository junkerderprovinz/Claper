defmodule Claper.Files do
  @moduledoc """
  Small helpers for looking at the files a presentation was converted into.

  There is one of them, and it exists because of a trap rather than because
  listing a directory needs a wrapper.
  """

  @doc """
  The `.jpg` files directly inside `dir`, in a stable order, or `[]`.

  `Path.wildcard("\#{dir}/*.jpg")` was the obvious way to write this and is
  wrong on Windows: the pattern is a glob, and in a glob a backslash escapes
  the character after it. A path like `C:\\Users\\...\\Temp` therefore matches
  nothing at all, whatever is in the directory. Nobody saw it in production,
  where Claper runs in a Linux container, but every developer running the tests
  on Windows saw three of them fail with "missing slides" against a directory
  that plainly held the slides.

  Listing the directory and filtering has no pattern in it, so there is nothing
  for a path to be misread as. The sort is by the number in the name, because
  these are slide 1, slide 2, slide 10, and asking a text sort for that order
  puts 10 between 1 and 2.
  """
  def jpgs_in(dir) when is_binary(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&(Path.extname(&1) |> String.downcase() == ".jpg"))
        |> Enum.sort_by(&slide_number/1)
        |> Enum.map(&Path.join(dir, &1))

      {:error, _reason} ->
        []
    end
  end

  def jpgs_in(_dir), do: []

  # A name that is not a number sorts after the numbered ones rather than
  # crashing the sort, and keeps its own order among its kind.
  defp slide_number(name) do
    case Integer.parse(Path.rootname(name)) do
      {number, ""} -> {0, number, name}
      _ -> {1, 0, name}
    end
  end
end
