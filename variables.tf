variable "region" {
  default = "ap-southeast-1" # Singapore
}

variable "availability_zones" {
  type    = list(string)
  default = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "vpc_cidr" { 
  default = "10.0.0.0/16" 
}