#-----------------------TAGS RELATED
variable "ENV" {
}

variable "TAGS" {
  type        = map(string)
  description = "REQUIRED - Tags to apply to the resources"
}

variable "PROJECT" {
  description = "Name of the project, used in a lot of the resource naming"
}


variable "REGION" {
  default = "eu-west-1"
}

variable "account_id"{
  
}

#-----------------------VPC RELATED
variable "vpc_id" {
  description = "sandbox  vpc id"
}

variable "web_subnet_ids" {
  description = "sandbox  web subnets ids"
}

variable "data_subnet_ids" {
  description = "sandbox  data subnets ids"
}


#-----KEY RELATED----------------------------------------
variable "kms_usage" {
  description = "Intended use for the key; options are ENCRYPT_DECREYPT or SIGN_VERIFY"
  default = "ENCRYPT_DECRYPT"
}

variable "key_spec" {
  description = "Specifies whether symmetric or assymetric + signing algorithms"
  default = "RSA_2048" #only for sandbox; other envs will use 4096
}

variable "pgp_kms_key_alias"{
  default = ""
}

variable "pgp_keyType"{
  default = "RSA"
}

variable "pgp_keyLength"{
  default = "2048"
}

variable "pgp_username"{
}

variable "pgp_email"{
}


data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

# PGP Keys
variable "pgp_pair_key_secret_name" {
  description = "Secret manager name for PGP key pair"
}

# PGP Import Keys
variable "pgp_file_name" {
  description = "file name of the public pgp key to import"
}

variable "pgp_file_path" {
  description = "file path of the public pgp key to import"
}

variable "pgp_public_key_secret_name" {
  description = "Id of secrets manager secret for pgp public key"
}