module "account_baseline" {
  source = "git::https://github.com/igor-platform-lab/terraform-modules.git//modules/account_baseline?ref=55c042f2753c907bf01cda102eea8a33756d2a39"

  state_bucket_name  = var.state_bucket_name
  github_role_name   = var.github_role_name
  github_subjects    = var.github_subjects
  github_policy_arns = var.github_policy_arns
}
