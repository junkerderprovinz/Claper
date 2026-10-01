defmodule Claper.Repo.Migrations.CreateEventsTokens do
  use Ecto.Migration

  def change do
    create table(:events_tokens) do
      add :token, :binary, null: false
      add :context, :string, null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(updated_at: false)
    end

    create index(:events_tokens, [:event_id])
    create unique_index(:events_tokens, [:context, :token])
  end
end
