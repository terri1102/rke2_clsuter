variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "RKE2 cluster name"
  type        = string
  default     = "mlops-test"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "key_name" {
  description = "EC2 SSH key pair name"
  type        = string
}

variable "rke2_version" {
  description = "RKE2 release version tag"
  type        = string
  default     = "v1.30.4+rke2r1"
}

variable "rke2_token" {
  description = "Shared secret for RKE2 cluster join"
  type        = string
  sensitive   = true
}

variable "control_plane" {
  type = object({
    count         = number
    instance_type = string
  })
  default = {
    count         = 3
    instance_type = "m5.large"
  }
}

variable "ceph_osd" {
  type = object({
    count         = number
    instance_type = string
    disk_gb       = number
  })
  default = {
    count         = 3
    instance_type = "m5.xlarge"
    disk_gb       = 200
  }
}

variable "worker" {
  type = object({
    count         = number
    instance_type = string
  })
  default = {
    count         = 2
    instance_type = "m5.xlarge"
  }
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_api_cidrs" {
  description = "CIDRs allowed to reach k8s API (6443)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
