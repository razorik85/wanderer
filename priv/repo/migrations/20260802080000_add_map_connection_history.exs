defmodule WandererApp.Repo.Migrations.AddMapConnectionHistory do
  use Ecto.Migration

  def up do
    create table(:map_connection_history_v1, primary_key: false) do
      add(:id, :uuid, null: false, primary_key: true)

      add(
        :map_id,
        references(:maps_v1,
          column: :id,
          name: "map_connection_history_v1_map_id_fkey",
          type: :uuid,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:solar_system_source, :bigint, null: false)
      add(:solar_system_target, :bigint, null: false)
      add(:type, :bigint, null: false, default: 0)
      add(:ship_size_type, :bigint)
      add(:wormhole_type, :text)
      add(:initial_mass_status, :bigint)
      add(:mass_status, :bigint)
      add(:initial_time_status, :bigint)
      add(:time_status, :bigint)
      add(:source_signature_eve_id, :text)
      add(:target_signature_eve_id, :text)
      add(:mass_tracking_started_at, :utc_datetime_usec)

      add(
        :opened_by_character_id,
        references(:character_v1,
          column: :id,
          name: "map_connection_history_v1_opened_by_character_id_fkey",
          type: :uuid,
          on_delete: :nilify_all
        )
      )

      add(
        :closed_by_character_id,
        references(:character_v1,
          column: :id,
          name: "map_connection_history_v1_closed_by_character_id_fkey",
          type: :uuid,
          on_delete: :nilify_all
        )
      )

      add(
        :closed_by_user_id,
        references(:user_v1,
          column: :id,
          name: "map_connection_history_v1_closed_by_user_id_fkey",
          type: :uuid,
          on_delete: :nilify_all
        )
      )

      add(:opened_at, :utc_datetime_usec, null: false)
      add(:eol_at, :utc_datetime_usec)
      add(:reduced_at, :utc_datetime_usec)
      add(:critical_at, :utc_datetime_usec)
      add(:closed_at, :utc_datetime_usec)
      add(:closure_reason, :text)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:map_connection_history_v1, [:map_id, :opened_at],
        name: "map_connection_history_v1_map_opened_at_index"
      )
    )

    create(
      index(:map_connection_history_v1, [:map_id, :closed_at],
        name: "map_connection_history_v1_map_closed_at_index"
      )
    )

    create(
      index(
        :map_connection_history_v1,
        [:map_id, :solar_system_source, :solar_system_target],
        name: "map_connection_history_v1_map_systems_index"
      )
    )

    alter table(:map_chain_passages_v1) do
      add(
        :connection_history_id,
        references(:map_connection_history_v1,
          column: :id,
          name: "map_chain_passages_v1_connection_history_id_fkey",
          type: :uuid,
          on_delete: :nilify_all
        )
      )
    end

    create(index(:map_chain_passages_v1, [:connection_history_id]))

    execute("""
    INSERT INTO map_connection_history_v1 (
      id, map_id, solar_system_source, solar_system_target, type, ship_size_type,
      wormhole_type, initial_mass_status, mass_status, initial_time_status, time_status,
      source_signature_eve_id, target_signature_eve_id, mass_tracking_started_at,
      opened_at, eol_at, reduced_at, critical_at, inserted_at, updated_at
    )
    SELECT
      id, map_id, solar_system_source, solar_system_target, COALESCE(type, 0), ship_size_type,
      wormhole_type, mass_status, mass_status, time_status, time_status,
      source_signature_eve_id, target_signature_eve_id, mass_tracking_started_at,
      inserted_at,
      CASE WHEN time_status = 1 THEN updated_at END,
      CASE WHEN COALESCE(mass_status, 0) >= 1 THEN updated_at END,
      CASE WHEN COALESCE(mass_status, 0) >= 2 THEN updated_at END,
      inserted_at, updated_at
    FROM map_chain_v1
    """)

    execute("""
    UPDATE map_chain_passages_v1 AS passage
       SET connection_history_id = connection.id
      FROM map_chain_v1 AS connection
     WHERE passage.map_id = connection.map_id
       AND passage.connection_history_id IS NULL
       AND passage.inserted_at >= connection.inserted_at
       AND (
         (passage.solar_system_source_id = connection.solar_system_source AND
          passage.solar_system_target_id = connection.solar_system_target)
         OR
         (passage.solar_system_source_id = connection.solar_system_target AND
          passage.solar_system_target_id = connection.solar_system_source)
       )
    """)

    execute("""
    CREATE OR REPLACE FUNCTION sync_map_connection_history_v1()
    RETURNS trigger AS $$
    DECLARE
      event_time timestamp without time zone := (now() AT TIME ZONE 'utc');
    BEGIN
      IF TG_OP = 'INSERT' THEN
        INSERT INTO map_connection_history_v1 (
          id, map_id, solar_system_source, solar_system_target, type, ship_size_type,
          wormhole_type, initial_mass_status, mass_status, initial_time_status, time_status,
          source_signature_eve_id, target_signature_eve_id, mass_tracking_started_at,
          opened_at, eol_at, reduced_at, critical_at, inserted_at, updated_at
        ) VALUES (
          NEW.id, NEW.map_id, NEW.solar_system_source, NEW.solar_system_target,
          COALESCE(NEW.type, 0), NEW.ship_size_type, NEW.wormhole_type,
          NEW.mass_status, NEW.mass_status, NEW.time_status, NEW.time_status,
          NEW.source_signature_eve_id, NEW.target_signature_eve_id,
          NEW.mass_tracking_started_at, NEW.inserted_at,
          CASE WHEN NEW.time_status = 1 THEN NEW.updated_at END,
          CASE WHEN COALESCE(NEW.mass_status, 0) >= 1 THEN NEW.updated_at END,
          CASE WHEN COALESCE(NEW.mass_status, 0) >= 2 THEN NEW.updated_at END,
          NEW.inserted_at, NEW.updated_at
        )
        ON CONFLICT (id) DO NOTHING;

        UPDATE map_chain_passages_v1 AS passage
           SET connection_history_id = NEW.id
         WHERE passage.map_id = NEW.map_id
           AND passage.connection_history_id IS NULL
           AND passage.inserted_at >= NEW.inserted_at - interval '30 seconds'
           AND (
             (passage.solar_system_source_id = NEW.solar_system_source AND
              passage.solar_system_target_id = NEW.solar_system_target)
             OR
             (passage.solar_system_source_id = NEW.solar_system_target AND
              passage.solar_system_target_id = NEW.solar_system_source)
           );

        RETURN NEW;
      ELSIF TG_OP = 'UPDATE' THEN
        UPDATE map_connection_history_v1
           SET solar_system_source = NEW.solar_system_source,
               solar_system_target = NEW.solar_system_target,
               type = COALESCE(NEW.type, 0),
               ship_size_type = NEW.ship_size_type,
               wormhole_type = NEW.wormhole_type,
               mass_status = NEW.mass_status,
               time_status = NEW.time_status,
               source_signature_eve_id = NEW.source_signature_eve_id,
               target_signature_eve_id = NEW.target_signature_eve_id,
               mass_tracking_started_at = NEW.mass_tracking_started_at,
               eol_at = CASE
                 WHEN eol_at IS NULL AND NEW.time_status = 1
                   THEN COALESCE(NEW.updated_at, event_time)
                 ELSE eol_at
               END,
               reduced_at = CASE
                 WHEN reduced_at IS NULL AND COALESCE(NEW.mass_status, 0) >= 1
                   THEN COALESCE(NEW.updated_at, event_time)
                 ELSE reduced_at
               END,
               critical_at = CASE
                 WHEN critical_at IS NULL AND COALESCE(NEW.mass_status, 0) >= 2
                   THEN COALESCE(NEW.updated_at, event_time)
                 ELSE critical_at
               END,
               updated_at = COALESCE(NEW.updated_at, event_time)
         WHERE id = NEW.id;

        RETURN NEW;
      ELSIF TG_OP = 'DELETE' THEN
        UPDATE map_connection_history_v1
           SET mass_status = OLD.mass_status,
               time_status = OLD.time_status,
               ship_size_type = OLD.ship_size_type,
               wormhole_type = OLD.wormhole_type,
               source_signature_eve_id = OLD.source_signature_eve_id,
               target_signature_eve_id = OLD.target_signature_eve_id,
               mass_tracking_started_at = OLD.mass_tracking_started_at,
               closed_at = COALESCE(closed_at, event_time),
               closure_reason = COALESCE(closure_reason, 'deleted'),
               updated_at = event_time
         WHERE id = OLD.id;

        RETURN OLD;
      END IF;

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER map_chain_v1_history_trigger
    AFTER INSERT OR UPDATE OR DELETE ON map_chain_v1
    FOR EACH ROW EXECUTE FUNCTION sync_map_connection_history_v1()
    """)

    execute("""
    CREATE OR REPLACE FUNCTION assign_map_connection_history_to_passage_v1()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.connection_history_id IS NULL THEN
        SELECT history.id
          INTO NEW.connection_history_id
          FROM map_connection_history_v1 AS history
         WHERE history.map_id = NEW.map_id
           AND history.closed_at IS NULL
           AND (
             (history.solar_system_source = NEW.solar_system_source_id AND
              history.solar_system_target = NEW.solar_system_target_id)
             OR
             (history.solar_system_source = NEW.solar_system_target_id AND
              history.solar_system_target = NEW.solar_system_source_id)
           )
         ORDER BY history.opened_at DESC
         LIMIT 1;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER map_chain_passages_v1_history_trigger
    BEFORE INSERT OR UPDATE OF map_id, solar_system_source_id, solar_system_target_id
    ON map_chain_passages_v1
    FOR EACH ROW EXECUTE FUNCTION assign_map_connection_history_to_passage_v1()
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS map_chain_passages_v1_history_trigger ON map_chain_passages_v1"
    )

    execute("DROP FUNCTION IF EXISTS assign_map_connection_history_to_passage_v1()")
    execute("DROP TRIGGER IF EXISTS map_chain_v1_history_trigger ON map_chain_v1")
    execute("DROP FUNCTION IF EXISTS sync_map_connection_history_v1()")

    drop_if_exists(index(:map_chain_passages_v1, [:connection_history_id]))

    alter table(:map_chain_passages_v1) do
      remove(:connection_history_id)
    end

    drop(table(:map_connection_history_v1))
  end
end
