variable "aws_region" {
  description = "AWS region where all resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name prefix used for resources in this deployment."
  type        = string
  default     = "n8n-demo"
}

variable "environment_name" {
  description = "Environment tag value used across all resources."
  type        = string
  default     = "demo"
}

variable "root_domain" {
  description = "Base domain that you control in your DNS provider (e.g. example.com)."
  type        = string
}

variable "subdomain" {
  description = "Subdomain that will point to n8n."
  type        = string
  default     = "n8n-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for n8n. t3.micro es elegible para Free Tier en us-east-1."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Size in GiB for the root volume."
  type        = number
  default     = 30
}

variable "data_volume_size" {
  description = "Size in GiB for the persistent data volume mounted at /opt/n8n."
  type        = number
  default     = 20
}

variable "docker_compose_version" {
  description = "Versión de Docker Compose CLI plugin a descargar."
  type        = string
  default     = "v2.27.0"
}

variable "default_timezone" {
  description = "Timezone used by n8n."
  type        = string
  default     = "UTC"
}

variable "letsencrypt_email" {
  description = "Optional email for Let's Encrypt/ACME notifications. Leave blank to skip."
  type        = string
  default     = ""
}

variable "n8n_basic_auth_user" {
  description = "Username for n8n basic authentication."
  type        = string
  sensitive   = true
}

variable "n8n_basic_auth_password" {
  description = "Password for n8n basic authentication."
  type        = string
  sensitive   = true
}
