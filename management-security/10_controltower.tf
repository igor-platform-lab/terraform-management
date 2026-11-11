resource "aws_controltower_landing_zone" "main" {
  version       = "4.0"
  manifest_json = file("${path.module}/../landing-zone.json")
}

locals {
  # Preencha após a landing zone estar ativa e a OU Workloads estar registrada.
  region_deny_control_arn = null # ARN global de CT.MULTISERVICE.PV.1 no Control Catalog.
  workloads_ou_arn        = null # ARN da OU Workloads na nova organização.
}

resource "aws_controltower_control" "workloads_region_deny" {
  count = local.region_deny_control_arn != null && local.workloads_ou_arn != null ? 1 : 0

  control_identifier = local.region_deny_control_arn
  target_identifier  = local.workloads_ou_arn

  parameters {
    key   = "AllowedRegions"
    value = jsonencode(["us-east-2"])
  }

  depends_on = [aws_controltower_landing_zone.main]
}
