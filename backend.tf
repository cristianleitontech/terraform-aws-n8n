terraform {
  backend "s3" {
    key          = "demo-n8n/demo/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
