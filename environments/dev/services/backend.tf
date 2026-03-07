terraform {
  backend "s3" {
    bucket         = "forge-terraform-state"
    key            = "dev/services/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "forge-terraform-locks"
    encrypt        = true
  }
}
