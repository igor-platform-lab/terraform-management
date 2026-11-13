module "versioned-bucket-config" {
  source          = "git::https://github.com/igor-platform-lab/terraform-modules.git//modules/config?ref=config-v0.1.0"
  depends_on      = [data.aws_organizations_account.org]
  region          = "us-east-2"
  name            = "Versioned Bucket"
  rule_identifier = "s3-bucket-versioning-enabled"
}
