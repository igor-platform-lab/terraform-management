resource "aws_config_organization_managed_rule" "example" {
  depends_on      = local.management_account
  region          = "us-east-2"
  name            = "Versioned Bucket"
  rule_identifier = "s3-bucket-versioning-enabled"
}
