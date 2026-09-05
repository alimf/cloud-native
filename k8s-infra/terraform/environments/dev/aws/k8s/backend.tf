terraform {
  backend "s3" {
    bucket       = "k8s-infra-dev-tfstate--use1-az4--x-s3"
    key          = "dev/k8s/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
