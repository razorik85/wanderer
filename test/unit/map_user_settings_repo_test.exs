defmodule WandererApp.MapUserSettingsRepoTest do
  use ExUnit.Case, async: true

  alias WandererApp.MapUserSettingsRepo

  test "adds an empty personal mass template list to existing user settings" do
    assert {:ok, %{"mass_templates" => [], "mass_tracking_enabled" => true}} =
             MapUserSettingsRepo.to_form_data(%{
               settings: Jason.encode!(%{"select_on_spash" => true})
             })
  end

  test "returns only the templates stored in the supplied user's settings" do
    templates = [
      %{
        "ship_type_id" => 47_466,
        "ship_type_name" => "Praxis",
        "label" => "Hot",
        "mass_tons" => 219_000
      }
    ]

    assert {:ok, %{"mass_templates" => ^templates, "mass_tracking_enabled" => true}} =
             MapUserSettingsRepo.to_form_data(%{
               settings: Jason.encode!(%{"mass_templates" => templates})
             })
  end

  test "keeps a user's disabled mass tracking preference" do
    assert {:ok, %{"mass_tracking_enabled" => false}} =
             MapUserSettingsRepo.to_form_data(%{
               settings: Jason.encode!(%{"mass_tracking_enabled" => false})
             })
  end
end
