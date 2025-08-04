variable "region" {
  default = "ap-southeast-1" # Singapore
}

variable "availability_zones" {
  type    = list(string)
  default = ["ap-southeast-1a", "ap-southeast-1b"]
}
