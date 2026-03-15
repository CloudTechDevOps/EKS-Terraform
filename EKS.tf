terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }

    helm = {
      source = "hashicorp/helm"
      version = "~> 2.9"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

############################
# VARIABLES
############################

variable "my_ip" {
  default = "0.0.0.0/0"
}

############################
# VPC
############################

resource "aws_vpc" "eks_vpc" {

  cidr_block = "10.0.0.0/16"

  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "eks-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id
}

############################
# SUBNETS
############################

resource "aws_subnet" "public1" {

  vpc_id = aws_vpc.eks_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  map_public_ip_on_launch = true
}

resource "aws_subnet" "public2" {

  vpc_id = aws_vpc.eks_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  map_public_ip_on_launch = true
}

resource "aws_subnet" "private1" {

  vpc_id = aws_vpc.eks_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private2" {

  vpc_id = aws_vpc.eks_vpc.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "us-east-1b"
}

############################
# NAT
############################

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {

  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.public1.id
}

############################
# ROUTES
############################

resource "aws_route_table" "public" {

  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "pub1" {
  subnet_id = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub2" {
  subnet_id = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}

############################
# IAM CLUSTER ROLE
############################

resource "aws_iam_role" "cluster_role" {

  name = "eks-cluster-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {

  role = aws_iam_role.cluster_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

############################
# WORKER ROLE
############################

resource "aws_iam_role" "worker_role" {

  name = "eks-worker-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_node" {

  role = aws_iam_role.worker_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni" {

  role = aws_iam_role.worker_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr" {

  role = aws_iam_role.worker_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

############################
# EKS CLUSTER
############################

resource "aws_eks_cluster" "eks" {

  name = "project-eks"

  role_arn = aws_iam_role.cluster_role.arn

  version = var.cluster_version

  vpc_config {

    subnet_ids = [
      aws_subnet.private1.id,
      aws_subnet.private2.id
    ]

    endpoint_public_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

############################
# NODE GROUP
############################

resource "aws_eks_node_group" "node_group" {

  cluster_name = aws_eks_cluster.eks.name

  node_group_name = "eks-node-group"

  node_role_arn = aws_iam_role.worker_role.arn

  version = var.node_group_version

  subnet_ids = [
    aws_subnet.private1.id,
    aws_subnet.private2.id
  ]

  instance_types = ["t3.medium"]

  scaling_config {

    desired_size = 2
    max_size = 4
    min_size = 1
  }
}

############################
# EKS ADDONS
############################

resource "aws_eks_addon" "vpc_cni" {

  cluster_name = aws_eks_cluster.eks.name
  addon_name = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {

  cluster_name = aws_eks_cluster.eks.name
  addon_name = "coredns"
}

resource "aws_eks_addon" "kube_proxy" {

  cluster_name = aws_eks_cluster.eks.name
  addon_name = "kube-proxy"
}

resource "aws_eks_addon" "pod_identity" {

  cluster_name = aws_eks_cluster.eks.name
  addon_name = "eks-pod-identity-agent"
}

resource "aws_eks_addon" "ebs_csi" {

  cluster_name = aws_eks_cluster.eks.name
  addon_name = "aws-ebs-csi-driver"
}
