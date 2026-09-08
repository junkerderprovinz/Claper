defmodule Claper.Addin.Pictures do
  @moduledoc """
  Stores the pictures the sidebar sends with a question.

  The sidebar is a web page in PowerPoint with no way to reach Claper's disk,
  so a picture arrives as base64 in the same request as the question it belongs
  to. It lands under the uploads directory the slides already use, which is
  what makes it served, backed up and deleted along with everything else rather
  than becoming a second kind of storage nobody remembers.

  Nothing here trusts the caller. The type is read out of the bytes rather than
  taken from the request, the size is capped, and the name is derived from the
  content, so two people sending the same picture store it once and nobody can
  choose where a file lands.
  """

  # Two megabytes. A picture on a slide is looked at from the back of a room,
  # not zoomed into, and every byte here travels through a request that also
  # carries the question.
  @max_bytes 2_000_000

  @doc """
  Writes one base64 picture and returns the path to serve it from.

  Accepts either a bare base64 string or a data URI, because a browser canvas
  hands over the second and a file reader the first. Returns `{:ok, path}`,
  `{:ok, nil}` when there was no picture to store, or `{:error, reason}`.
  """
  def store(nil), do: {:ok, nil}
  def store(""), do: {:ok, nil}

  def store(value) when is_binary(value) do
    with {:ok, raw} <- decode(value),
         :ok <- within_size(raw),
         {:ok, extension} <- type_of(raw),
         {:ok, path} <- write(raw, extension) do
      {:ok, path}
    end
  end

  def store(_value), do: {:error, "a picture has to be sent as text"}

  defp decode(value) do
    payload =
      case String.split(value, ",", parts: 2) do
        ["data:" <> _head, rest] -> rest
        _ -> value
      end

    case Base.decode64(String.trim(payload)) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, "the picture is not valid base64"}
    end
  end

  defp within_size(raw) when byte_size(raw) > @max_bytes,
    do: {:error, "the picture is larger than 2 MB"}

  defp within_size(_raw), do: :ok

  # Read out of the bytes, never out of the request. A caller naming its own
  # type is a caller choosing what ends up on disk with what extension.
  defp type_of(<<0x89, "PNG\r\n", 0x1A, "\n", _rest::binary>>), do: {:ok, "png"}
  defp type_of(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "jpg"}
  defp type_of(<<"GIF87a", _rest::binary>>), do: {:ok, "gif"}
  defp type_of(<<"GIF89a", _rest::binary>>), do: {:ok, "gif"}
  defp type_of(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: {:ok, "webp"}
  defp type_of(_raw), do: {:error, "only PNG, JPEG, GIF and WebP pictures are accepted"}

  defp write(raw, extension) do
    # Named after the content, so the same picture sent twice is stored once and
    # nobody can pick the name a file lands under.
    name = "#{:crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)}.#{extension}"
    dir = Path.join([storage_dir(), "uploads", "addin"])

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(Path.join(dir, name), raw) do
      {:ok, "/uploads/addin/#{name}"}
    else
      {:error, reason} -> {:error, "the picture could not be stored: #{inspect(reason)}"}
    end
  end

  defp storage_dir, do: Application.get_env(:claper, :storage_dir)
end
