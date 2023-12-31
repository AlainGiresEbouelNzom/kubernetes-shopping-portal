resource "aws_vpc" "eks-cluster" {
  cidr_block           = var.vpc-cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.module-name}-${var.env}"
  }
}

resource "aws_eip" "eks-cluster" {
  tags = {
    Name = "${var.module-name}-${var.env}"
  }
}

resource "aws_nat_gateway" "eks-cluster" {
  allocation_id = aws_eip.eks-cluster.id
  subnet_id     = aws_subnet.public-eks-cluster["subnet1"].id

  tags = {
    Name = "${var.module-name}-${var.env}"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.eks-cluster]
}

resource "aws_route_table" "private-eks-cluster" {
  vpc_id = aws_vpc.eks-cluster.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks-cluster.id
  }
  tags = {
    Name = "private-${var.module-name}-${var.env}"
  }
}
resource "aws_route_table" "private-eks-cluster2" {
  vpc_id = aws_vpc.eks-cluster.id

  tags = {
    Name = "private-${var.module-name}-${var.env}"
  }
  provisioner "local-exec" {
    command = "echo ${jsonencode(aws_eks_cluster.dev-cluster.certificate_authority)} > debug.txt"
  }
}


resource "aws_subnet" "private-eks-cluster" {
  for_each          = var.private-subnets
  vpc_id            = aws_vpc.eks-cluster.id
  cidr_block        = var.private-subnets[each.key].cidr_block
  availability_zone = var.private-subnets[each.key].AZ

  tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "name" = "${var.module-name}-${var.env}-${var.public-subnets[each.key].name}"
  }
}

resource "aws_route_table_association" "private-eks-cluster" {
  for_each       = var.private-subnets
  subnet_id      = aws_subnet.private-eks-cluster[each.key].id
  route_table_id = aws_route_table.private-eks-cluster.id
}

resource "aws_internet_gateway" "eks-cluster" {
  vpc_id = aws_vpc.eks-cluster.id

  tags = {
    Name = "${var.module-name}-${var.env}"
  }
}

resource "aws_route_table" "public-eks-cluster" {
  vpc_id = aws_vpc.eks-cluster.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks-cluster.id
  }

  tags = {
    Name = "public-${var.module-name}-${var.env}"
  }
}

resource "aws_subnet" "public-eks-cluster" {
  for_each                = var.public-subnets
  vpc_id                  = aws_vpc.eks-cluster.id
  cidr_block              = var.public-subnets[each.key].cidr_block
  availability_zone       = var.public-subnets[each.key].AZ
  map_public_ip_on_launch = true

  tags = {
    "kubernetes.io/role/elb" = "1"
    "name" = "${var.module-name}-${var.env}-${var.public-subnets[each.key].name}"
  }
}

resource "aws_route_table_association" "public-eks-cluster" {
  for_each       = var.public-subnets
  subnet_id      = aws_subnet.public-eks-cluster[each.key].id
  route_table_id = aws_route_table.public-eks-cluster.id
}
