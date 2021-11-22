# Create VPC 

resource "aws_vpc" "demo" {
  cidr_block = "192.168.0.0/16"

  instance_tenancy = "default"

  enable_dns_support = true

  enable_dns_hostnames = true

  tags = {
    Name = "main"
  }

}

output "vpc_id" {
  value       = aws_vpc.demo.id
  description = "VPC id"
  sensitive   = false
}

// Internet gateway

resource "aws_internet_gateway" "demo" {

  vpc_id = aws_vpc.demo.id

  tags = {
    "Name" = "demo"
  }
}

// Subnets

resource "aws_subnet" "public_1" {
  vpc_id     = aws_vpc.demo.id
  cidr_block = "192.168.0.0/18"

  availability_zone = "us-east-1a"

  map_public_ip_on_launch = true

  tags = {
    "Name"                      = "public-us-east-1a"
    "kubernetes.io/cluster/eks" = "shared"
    "kubernetes.io/role/elb"    = 1
  }
}

resource "aws_subnet" "public_2" {
  vpc_id     = aws_vpc.demo.id
  cidr_block = "192.168.64.0/18"

  availability_zone = "us-east-1b"

  map_public_ip_on_launch = true

  tags = {
    "Name"                      = "public-us-east-1b"
    "kubernetes.io/cluster/eks" = "shared"
    "kubernetes.io/role/elb"    = 1
  }
}

resource "aws_subnet" "private_1" {
  vpc_id     = aws_vpc.demo.id
  cidr_block = "192.168.128.0/18"

  availability_zone = "us-east-1a"

  map_public_ip_on_launch = true

  tags = {
    "Name"                            = "private-us-east-1a"
    "kubernetes.io/cluster/eks"       = "shared"
    "kubernetes.io/role/internal-elb" = 1
  }
}
resource "aws_subnet" "private_2" {
  vpc_id     = aws_vpc.demo.id
  cidr_block = "192.168.192.0/18"

  availability_zone = "us-east-1b"

  map_public_ip_on_launch = true

  tags = {
    "Name"                            = "private-us-east-1b"
    "kubernetes.io/cluster/eks"       = "shared"
    "kubernetes.io/role/internal-elb" = 1
  }
}

//Elastic ip address

resource "aws_eip" "nat1" {
  depends_on = [
    aws_internet_gateway.demo
  ]
}

resource "aws_eip" "nat2" {
  depends_on = [
    aws_internet_gateway.demo
  ]
}

//NAT gateways
//Connection of private with public

resource "aws_nat_gateway" "gw1" {
  allocation_id = aws_eip.nat1.id

  subnet_id = aws_subnet.public_1.id

  tags = {
    "Name" = "NAT 1"
  }
}

resource "aws_nat_gateway" "gw2" {
  allocation_id = aws_eip.nat2.id

  subnet_id = aws_subnet.public_2.id

  tags = {
    "Name" = "NAT 2"
  }
}

//Routing tables

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }

  tags = {
    "Name" = "public"
  }
}

resource "aws_route_table" "private1" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gw1.id
  }

  tags = {
    "Name" = "private1"
  }
}
resource "aws_route_table" "private2" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gw2.id
  }

  tags = {
    "Name" = "private2"
  }
}

//Route table associations

resource "aws_route_table_association" "public1" {

  subnet_id = aws_subnet.public_1.id

  route_table_id = aws_route_table.public.id

}

resource "aws_route_table_association" "public2" {

  subnet_id = aws_subnet.public_2.id

  route_table_id = aws_route_table.public.id

}

resource "aws_route_table_association" "private1" {

  subnet_id = aws_subnet.private_1.id

  route_table_id = aws_route_table.private1.id

}

resource "aws_route_table_association" "private2" {

  subnet_id = aws_subnet.private_2.id

  route_table_id = aws_route_table.private2.id

}

// EKS Kubernetes cluster

//role for eks
resource "aws_iam_role" "eks_cluster" {
  # The name of the role
  name = "eks-cluster"

  # The policy that grants an entity permission to assume the role.
  # Used to access AWS resources that you might not normally have access to.
  # The role that Amazon EKS will use to create AWS resources for Kubernetes clusters
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cluster_policy" {
  # The ARN of the policy you want to apply
  # https://github.com/SummitRoute/aws_managed_policies/blob/master/policies/AmazonEKSClusterPolicy
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

  # The role the policy should be applied to
  role = aws_iam_role.eks_cluster.name
}

resource "aws_eks_cluster" "eks" {
  # Name of the cluster.
  name = "eks"

  role_arn = aws_iam_role.eks_cluster.arn


  vpc_config {
    endpoint_private_access = false

    endpoint_public_access = true

    subnet_ids = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id,
      aws_subnet.private_1.id,
      aws_subnet.private_2.id
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_cluster_policy
  ]
}

output "eks_name" {
  value       = aws_eks_cluster.eks.name
  description = "EKS name"
  sensitive   = false
}

//nodes
resource "aws_iam_role" "nodes_general" {
  name = "eks-node-group-general"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      }, 
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}


resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy_general" {
  # The ARN of the policy you want to apply.
  # https://github.com/SummitRoute/aws_managed_policies/blob/master/policies/AmazonEKSWorkerNodePolicy
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"

  # The role the policy should be applied to
  role = aws_iam_role.nodes_general.name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy_general" {
  # The ARN of the policy you want to apply.
  # https://github.com/SummitRoute/aws_managed_policies/blob/master/policies/AmazonEKS_CNI_Policy
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"

  # The role the policy should be applied to
  role = aws_iam_role.nodes_general.name
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  # The ARN of the policy you want to apply.
  # https://github.com/SummitRoute/aws_managed_policies/blob/master/policies/AmazonEC2ContainerRegistryReadOnly
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"

  # The role the policy should be applied to
  role = aws_iam_role.nodes_general.name
}

# Resource: aws_eks_node_group
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group

resource "aws_eks_node_group" "nodes_general" {
  cluster_name = aws_eks_cluster.eks.name

  node_group_name = "nodes-general"

  node_role_arn = aws_iam_role.nodes_general.arn

  subnet_ids = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]

  scaling_config {
    desired_size = 1

    max_size = 2

    min_size = 1
  }

  ami_type = "AL2_x86_64"

  capacity_type = "ON_DEMAND"

  disk_size = 20

  force_update_version = false

  instance_types = ["t3.small"]

  labels = {
    role = "nodes-general"
  }


  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy_general,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy_general,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
  ]
}







