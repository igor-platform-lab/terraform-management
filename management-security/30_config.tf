module "versioned-bucket-config" {
  source           = "git::https://github.com/igor-platform-lab/terraform-modules.git//modules/config?ref=config-v0.1.1"
  config_rule_name = "Versioned Bucket"
  rule             = "s3-bucket-versioning-enabled"
}
