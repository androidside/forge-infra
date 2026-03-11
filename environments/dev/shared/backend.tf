terraform {
  backend "s3" {
    bucket         = "forge-terraform-state-263618685979"
    key            = "dev/shared/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "forge-terraform-locks"
    encrypt        = true
  }
}
