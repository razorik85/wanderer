defmodule WandererApp.Repo.Migrations.AddMassConfirmationToMapChainPassages do
  use Ecto.Migration

  def up do
    alter table(:map_chain_passages_v1) do
      add :mass_confirmed_at, :utc_datetime_usec

      add :mass_confirmed_by_id,
          references(:user_v1,
            column: :id,
            name: "map_chain_passages_v1_mass_confirmed_by_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all
          )
    end

    create index(:map_chain_passages_v1, [:mass_confirmed_at])
    create index(:map_chain_passages_v1, [:mass_confirmed_by_id])
  end

  def down do
    drop constraint(
           :map_chain_passages_v1,
           "map_chain_passages_v1_mass_confirmed_by_id_fkey"
         )

    alter table(:map_chain_passages_v1) do
      remove :mass_confirmed_at
      remove :mass_confirmed_by_id
    end
  end
end
