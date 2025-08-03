provider "aws" {
  region = var.region
}

terraform {
  required_version = ">= 1.12.0"    
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  cluster_name = "api-eks-cluster"
}

resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "simple-golang-api-vpc"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags = {
    Name = "simple-golang-api-igw"
  }  
}

resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.natgw.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    Name = "simple-golang-api-natgw"
  }  
}

resource "aws_eip" "natgw" {
  tags = {
    Name = "simple-golang-api-eip-natgw"
  }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 4, count.index)
  availability_zone = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "simple-golang-api-subnet-public-${count.index}"
    "kubernetes.io/role/elb" = "1"
    "mapPublicIpOnLaunch" = "TRUE"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 4, count.index + 2)
  availability_zone = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name = "simple-golang-api-subnet-private-${count.index}"
    "kubernetes.io/role/internal-elb" = "1",
    "mapPublicIpOnLaunch"             = "FALSE"
    "karpenter.sh/discovery"          = local.cluster_name
    "kubernetes.io/role/cni"          = "1"    
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "simple-golang-api-route-table-public"
  }  
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgw.id
  }
  tags = {
    Name = "simple-golang-api-route-table-private"
  }  
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

data "aws_iam_policy_document" "eks_assume_role_policy" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role_policy.json
}

resource "aws_iam_role_policy_attachments_exclusive" "cluster" {
  role_name = aws_iam_role.eks_cluster.name
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
  ]
}

data "aws_iam_policy_document" "eks_node_assume_role_policy" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role_policy.json
}

resource "aws_iam_role_policy_attachments_exclusive" "node" {
  role_name = aws_iam_role.eks_node.name
  policy_arns = [
   "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
  ]
}

resource "aws_eks_cluster" "eks" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.33"

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    security_group_ids      = []
    endpoint_private_access = "true"
    endpoint_public_access  = "true"
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = "true"
  }

  bootstrap_self_managed_addons = "false"

  zonal_shift_config {
    enabled = true
  }

  compute_config {
    enabled       = "true"
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.eks_node.arn
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = "true"
    }
  }

  storage_config {
    block_storage {
      enabled = "true"
    }
  }
 
  upgrade_policy {
    support_type = "STANDARD"
  }
    
 depends_on = [aws_iam_role.eks_cluster]

}