defmodule WandererApp.Repo.Migrations.AddMassTrackingLifecycleToMapConnections do
  use Ecto.Migration

  def change do
    alter table(:map_chain_v1) do
      add :mass_tracking_started_at, :utc_datetime_usec
      add :source_signature_eve_id, :text
      add :target_signature_eve_id, :text
    end
  end
end
