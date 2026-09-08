defmodule Claper.Addin.PicturesTest do
  @moduledoc """
  The pictures the sidebar sends with a question.

  Everything here arrives from a web page inside PowerPoint, so the tests are
  mostly about what is refused: the type is read out of the bytes rather than
  taken from the request, and the name is derived from the content so nobody
  can choose where a file lands.
  """

  use ExUnit.Case, async: false

  alias Claper.Addin.Pictures

  @png <<0x89, "PNG\r\n", 0x1A, "\n", "the rest does not matter">>
  @jpeg <<0xFF, 0xD8, 0xFF, "and some more">>
  @gif <<"GIF89a", "and some more">>

  setup do
    dir = Path.join(System.tmp_dir!(), "claper-pictures-#{System.unique_integer([:positive])}")
    previous = Application.get_env(:claper, :storage_dir)
    Application.put_env(:claper, :storage_dir, dir)

    on_exit(fn ->
      Application.put_env(:claper, :storage_dir, previous)
      File.rm_rf(dir)
    end)

    %{dir: dir}
  end

  test "nothing sent is nothing stored" do
    assert Pictures.store(nil) == {:ok, nil}
    assert Pictures.store("") == {:ok, nil}
  end

  test "a picture lands under uploads and is served from there", %{dir: dir} do
    assert {:ok, path} = Pictures.store(Base.encode64(@png))
    assert String.starts_with?(path, "/uploads/addin/")
    assert String.ends_with?(path, ".png")
    assert File.exists?(Path.join([dir, "uploads", "addin", Path.basename(path)]))
  end

  # A browser canvas hands over a data URI and a file reader a bare string.
  test "a data URI and bare base64 are the same picture" do
    assert {:ok, bare} = Pictures.store(Base.encode64(@png))
    assert {:ok, uri} = Pictures.store("data:image/png;base64," <> Base.encode64(@png))
    assert bare == uri
  end

  test "the type comes out of the bytes, not out of the request" do
    assert {:ok, jpeg} = Pictures.store(Base.encode64(@jpeg))
    assert String.ends_with?(jpeg, ".jpg")

    assert {:ok, gif} = Pictures.store(Base.encode64(@gif))
    assert String.ends_with?(gif, ".gif")

    # A name is not a type. Whatever this claims to be, it is not a picture.
    assert {:error, message} =
             Pictures.store("data:image/png;base64," <> Base.encode64("<?php echo 1; ?>"))

    assert message =~ "PNG"
  end

  test "something that is not base64 at all is refused" do
    assert {:error, message} = Pictures.store("not base64 at all !!!")
    assert message =~ "base64"
  end

  test "a picture over the size cap is refused rather than written", %{dir: dir} do
    huge = @png <> :binary.copy("x", 2_000_001)
    assert {:error, message} = Pictures.store(Base.encode64(huge))
    assert message =~ "2 MB"
    refute File.exists?(Path.join([dir, "uploads", "addin"]))
  end

  # Named after its content, so the same picture twice is stored once and the
  # caller has no say in the name.
  test "the same picture twice is one file" do
    assert {:ok, first} = Pictures.store(Base.encode64(@png))
    assert {:ok, second} = Pictures.store(Base.encode64(@png))
    assert first == second
  end
end
