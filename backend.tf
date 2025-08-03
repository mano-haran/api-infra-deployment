terraform {
  backend "s3" {
    bucket         = "s3-tfstate-golang-api"
    key            = "env-name/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-lock-table"
    encrypt        = true
  }
}
