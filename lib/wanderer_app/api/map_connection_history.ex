defmodule WandererApp.Api.MapConnectionHistory do
  @moduledoc false

  use Ash.Resource,
    domain: WandererApp.Api,
    data_layer: AshPostgres.DataLayer,
    primary_read_warning?: false

  postgres do
    repo(WandererApp.Repo)
    table("map_connection_history_v1")
  end

  code_interface do
    define(:by_id, get_by: [:id], action: :read)
    define(:by_map, action: :by_map)
    define(:annotate_open, action: :annotate_open)
    define(:prepare_close, action: :prepare_close)
  end

  actions do
    read :read do
      primary?(true)
    end

    read :by_map do
      argument(:map_id, :string, allow_nil?: false)
      filter(expr(map_id == ^arg(:map_id)))
    end

    update :annotate_open do
      accept([:opened_by_character_id])
      require_atomic?(false)
    end

    update :prepare_close do
      accept([:closure_reason, :closed_by_character_id, :closed_by_user_id])
      require_atomic?(false)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :solar_system_source, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :solar_system_target, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :type, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute(:ship_size_type, :integer, public?: true)
    attribute(:wormhole_type, :string, public?: true)
    attribute(:initial_mass_status, :integer, public?: true)
    attribute(:mass_status, :integer, public?: true)
    attribute(:initial_time_status, :integer, public?: true)
    attribute(:time_status, :integer, public?: true)
    attribute(:source_signature_eve_id, :string, public?: true)
    attribute(:target_signature_eve_id, :string, public?: true)
    attribute(:mass_tracking_started_at, :utc_datetime_usec, public?: true)
    attribute(:opened_at, :utc_datetime_usec, allow_nil?: false, public?: true)
    attribute(:eol_at, :utc_datetime_usec, public?: true)
    attribute(:reduced_at, :utc_datetime_usec, public?: true)
    attribute(:critical_at, :utc_datetime_usec, public?: true)
    attribute(:closed_at, :utc_datetime_usec, public?: true)
    attribute(:closure_reason, :string, public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :map, WandererApp.Api.Map do
      allow_nil?(false)
      attribute_writable?(false)
      public?(true)
    end

    belongs_to :opened_by_character, WandererApp.Api.Character do
      allow_nil?(true)
      attribute_writable?(true)
      public?(true)
    end

    belongs_to :closed_by_character, WandererApp.Api.Character do
      allow_nil?(true)
      attribute_writable?(true)
      public?(true)
    end

    belongs_to :closed_by_user, WandererApp.Api.User do
      allow_nil?(true)
      attribute_writable?(true)
      public?(true)
    end
  end
end
