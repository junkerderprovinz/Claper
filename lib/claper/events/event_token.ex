defmodule Claper.Events.EventToken do
  @moduledoc """
  Event scoped tokens.

  The only context today is `"presenter_embed"`: a revocable, per event
  capability that grants read-only access to the presenter view without an
  interactive login, so the view can be framed by a third party such as the
  PowerPoint web viewer.

  Only the SHA-256 hash of the token is stored, following
  `Claper.Accounts.UserToken`. The raw value is returned once, when the token is
  built, and cannot be reconstructed from the database.
  """

  use Ecto.Schema
  import Ecto.Query

  alias Claper.Events.Event

  @hash_algorithm :sha256
  @rand_size 32

  @presenter_embed_context "presenter_embed"

  schema "events_tokens" do
    field :token, :binary
    field :context, :string

    belongs_to :event, Claper.Events.Event
    belongs_to :created_by, Claper.Accounts.User

    timestamps(updated_at: false)
  end

  @doc """
  The context string used for embeddable presenter links.
  """
  def presenter_embed_context, do: @presenter_embed_context

  @doc """
  Builds a presenter embed token and its hash.

  Returns `{encoded_token, event_token_struct}`. The encoded token is the only
  copy of the secret, the struct carries its hash for storage.
  """
  def build_presenter_embed_token(%Event{} = event, %Claper.Accounts.User{} = user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: hashed_token,
       context: @presenter_embed_context,
       event_id: event.id,
       created_by_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the event the token was issued for, if any. The event
  lifetime is part of the same query, using the condition
  `Claper.Events.get_event_with_code/2` already applies, so an embed link can
  never outlive its event.
  """
  def verify_presenter_embed_token_query(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} when byte_size(decoded_token) == @rand_size ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        now = NaiveDateTime.utc_now()

        query =
          from t in __MODULE__,
            join: e in Event,
            on: e.id == t.event_id,
            where:
              t.token == ^hashed_token and t.context == ^@presenter_embed_context and
                (is_nil(e.expired_at) or e.expired_at > ^now),
            select: e

        {:ok, query}

      _ ->
        :error
    end
  end

  def verify_presenter_embed_token_query(_token), do: :error

  @doc """
  Gets all tokens for the given event for the given contexts.
  """
  def event_and_contexts_query(%Event{} = event, [_ | _] = contexts) do
    from t in __MODULE__, where: t.event_id == ^event.id and t.context in ^contexts
  end
end
