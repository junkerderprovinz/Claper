defmodule Claper.Events.EventToken do
  @moduledoc """
  Event scoped tokens, stored as SHA-256 hashes like `Claper.Accounts.UserToken`.

  A `"presenter_embed"` token gives read-only access to the presenter view and
  ends up inside shared slide decks. An `"addin"` token lets the PowerPoint
  sidebar create polls, so it is kept out of documents.
  """

  use Ecto.Schema
  import Ecto.Query

  alias Claper.Events.Event

  @hash_algorithm :sha256
  @rand_size 32

  @presenter_embed_context "presenter_embed"
  @addin_context "addin"

  schema "events_tokens" do
    field :token, :binary
    field :context, :string

    belongs_to :event, Claper.Events.Event
    belongs_to :created_by, Claper.Accounts.User

    timestamps(updated_at: false)
  end

  @doc """
  Returns the context string used for embeddable presenter links.
  """
  def presenter_embed_context, do: @presenter_embed_context

  @doc """
  Returns the context string used for PowerPoint sidebar tokens.
  """
  def addin_context, do: @addin_context

  @doc """
  Builds a sidebar token and its hash.
  """
  def build_addin_token(%Event{} = event, %Claper.Accounts.User{} = user) do
    build_token(event, user, @addin_context)
  end

  @doc """
  Checks if the sidebar token is valid and returns its underlying lookup query.
  """
  def verify_addin_token_query(token), do: verify_token_query(token, @addin_context)

  @doc """
  Builds a presenter embed token and its hash.

  Returns `{encoded_token, event_token_struct}`.
  """
  def build_presenter_embed_token(%Event{} = event, %Claper.Accounts.User{} = user) do
    build_token(event, user, @presenter_embed_context)
  end

  defp build_token(%Event{} = event, %Claper.Accounts.User{} = user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: hashed_token,
       context: context,
       event_id: event.id,
       created_by_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the token's event, as long as that event has not expired.
  """
  def verify_presenter_embed_token_query(token),
    do: verify_token_query(token, @presenter_embed_context)

  defp verify_token_query(token, context) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} when byte_size(decoded_token) == @rand_size ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        now = NaiveDateTime.utc_now()

        query =
          from t in __MODULE__,
            join: e in Event,
            on: e.id == t.event_id,
            where:
              t.token == ^hashed_token and t.context == ^context and
                (is_nil(e.expired_at) or e.expired_at > ^now),
            select: e

        {:ok, query}

      _ ->
        :error
    end
  end

  defp verify_token_query(_token, _context), do: :error

  @doc """
  Gets all tokens for the given event for the given contexts.
  """
  def event_and_contexts_query(%Event{} = event, [_ | _] = contexts) do
    from t in __MODULE__, where: t.event_id == ^event.id and t.context in ^contexts
  end
end
