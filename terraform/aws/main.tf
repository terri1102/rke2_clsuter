terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "personal-account"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  azs        = slice(data.aws_availability_zones.available.names, 0, 3)
  name_prefix = "${var.cluster_name}"
}

# ─── VPC ─────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${local.name_prefix}-subnet-${count.index}" }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.main.id
}

# ─── Security Groups ─────────────────────────────────────────────────────────

resource "aws_security_group" "cluster" {
  name        = "${local.name_prefix}-cluster"
  description = "RKE2 cluster internal + external access"
  vpc_id      = aws_vpc.main.id

  # full intra-cluster communication
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description = "K8s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.allowed_api_cidrs
  }

  ingress {
    description = "HTTP Ingress"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS Ingress"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg" }
}

# ─── IAM (SSM Session Manager fallback) ──────────────────────────────────────

resource "aws_iam_instance_profile" "node" {
  name = "${local.name_prefix}-node-profile"
  role = aws_iam_role.node.name
}

resource "aws_iam_role" "node" {
  name = "${local.name_prefix}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ─── Control Plane nodes ──────────────────────────────────────────────────────

# cp-0: cluster initializer
resource "aws_instance" "control_plane" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.control_plane.instance_type
  subnet_id     = aws_subnet.public[0].id
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/control-plane.sh.tpl", {
    rke2_version   = var.rke2_version
    rke2_token     = var.rke2_token
    cluster_name   = var.cluster_name
    init_server    = true
    first_cp_ip    = ""
  }))

  tags = {
    Name                                        = "${local.name_prefix}-cp-0"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Role                                        = "control-plane"
  }
}

# cp-1, cp-2: join after cp-0 is ready
resource "aws_instance" "control_plane_join" {
  count         = var.control_plane.count - 1
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.control_plane.instance_type
  subnet_id     = aws_subnet.public[count.index + 1].id
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/control-plane.sh.tpl", {
    rke2_version   = var.rke2_version
    rke2_token     = var.rke2_token
    cluster_name   = var.cluster_name
    init_server    = false
    first_cp_ip    = aws_instance.control_plane.private_ip
  }))

  tags = {
    Name                                        = "${local.name_prefix}-cp-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Role                                        = "control-plane"
  }

  depends_on = [aws_instance.control_plane]
}

# ─── Ceph OSD nodes ───────────────────────────────────────────────────────────

resource "aws_instance" "ceph_osd" {
  count         = var.ceph_osd.count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.ceph_osd.instance_type
  subnet_id     = aws_subnet.public[count.index % 3].id
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/agent.sh.tpl", {
    rke2_version    = var.rke2_version
    rke2_token      = var.rke2_token
    server_url      = "https://${aws_instance.control_plane.private_ip}:9345"
    node_labels     = "node-role.rook-ceph/osd=true"
    node_taints     = "storage=ceph:NoSchedule"
  }))

  tags = {
    Name                                      = "${local.name_prefix}-ceph-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Role                                      = "ceph-osd"
  }

  depends_on = [aws_instance.control_plane]
}

# Dedicated EBS volume for Ceph OSD (raw block, no filesystem)
resource "aws_ebs_volume" "ceph_osd" {
  count             = var.ceph_osd.count
  availability_zone = aws_instance.ceph_osd[count.index].availability_zone
  size              = var.ceph_osd.disk_gb
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${local.name_prefix}-ceph-osd-${count.index}" }
}

resource "aws_volume_attachment" "ceph_osd" {
  count       = var.ceph_osd.count
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.ceph_osd[count.index].id
  instance_id = aws_instance.ceph_osd[count.index].id
}

# ─── Worker nodes ─────────────────────────────────────────────────────────────

resource "aws_instance" "worker" {
  count         = var.worker.count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker.instance_type
  subnet_id     = aws_subnet.public[count.index % 3].id
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 100
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/agent.sh.tpl", {
    rke2_version = var.rke2_version
    rke2_token   = var.rke2_token
    server_url   = "https://${aws_instance.control_plane.private_ip}:9345"
    # worker-0 gets ingress-ready label — EIP is attached to this node
    node_labels  = count.index == 0 ? "ingress-ready=true" : ""
    node_taints  = ""
  }))

  tags = {
    Name                                        = "${local.name_prefix}-worker-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Role                                        = "worker"
  }

  depends_on = [aws_instance.control_plane]
}

# ─── Elastic IP for Ingress (worker-0) ───────────────────────────────────────

resource "aws_eip" "ingress" {
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-ingress-eip" }
}

resource "aws_eip_association" "ingress" {
  instance_id   = aws_instance.worker[0].id
  allocation_id = aws_eip.ingress.id
}
