defmodule SootCore.Domain do
  @moduledoc """
  Ash domain for `soot_core` resources.
  """
  use Ash.Domain, otp_app: :soot_core, validate_config_inclusion?: false

  resources do
    allow_unregistered? true

    resource SootCore.Tenant
    resource SootCore.SerialScheme
    resource SootCore.ProductionBatch
    resource SootCore.Device
    resource SootCore.DeviceShadow
    resource SootCore.EnrollmentToken
  end
end
