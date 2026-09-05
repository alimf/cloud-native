terraform {
  backend "s3" {
    bucket         = "k8s-infra-dev-us-east-1"
    key            = "dev/aws/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}