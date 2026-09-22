module "permission_set_adm" {
  source = "../modules/permission_set"

  name = "administratorPermissionSet"

  account_ids = [
    "965480031349"
  ]

  principals = {
    admin_user = {
      type = "USER"
      id   = "c15b6580-e0c1-7037-a2cd-b2593692644e"
    }
  }

  managed_policy_arn = [
    "arn:aws:iam::aws:policy/AdministratorAccess"
  ]
}