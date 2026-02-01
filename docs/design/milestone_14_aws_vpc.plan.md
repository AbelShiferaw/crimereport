# Milestone 14: AWS Account & VPC

## Goal
Set up AWS infrastructure foundation: VPC, subnets, security groups, and IAM roles needed for the backend.

## Dependencies
Requires AWS account with admin access.

## Implementation

### 1. VPC Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                         VPC (10.0.0.0/16)                   │
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │  Public Subnet A    │    │  Public Subnet B    │        │
│  │  10.0.1.0/24        │    │  10.0.2.0/24        │        │
│  │  - ALB              │    │  - ALB              │        │
│  │  - NAT Gateway      │    │                     │        │
│  └─────────────────────┘    └─────────────────────┘        │
│                                                             │
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │  Private Subnet A   │    │  Private Subnet B   │        │
│  │  10.0.10.0/24       │    │  10.0.11.0/24       │        │
│  │  - ECS Tasks        │    │  - ECS Tasks        │        │
│  │  - Aurora           │    │  - Aurora           │        │
│  │  - Redis            │    │  - Redis            │        │
│  └─────────────────────┘    └─────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### 2. Terraform/CloudFormation Setup
```hcl
# infrastructure/vpc.tf

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = { Name = "reportcrime-vpc" }
}

# Public subnets (for ALB)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "reportcrime-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "reportcrime-public-b" }
}

# Private subnets (for ECS, Aurora, Redis)
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "reportcrime-private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "reportcrime-private-b" }
}
```

### 3. Internet & NAT Gateway
```hcl
# Internet Gateway (public internet access)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# NAT Gateway (private subnet outbound)
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}
```

### 4. Security Groups
```hcl
# ALB Security Group
resource "aws_security_group" "alb" {
  name   = "reportcrime-alb-sg"
  vpc_id = aws_vpc.main.id
  
  ingress {
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
}

# ECS Tasks Security Group
resource "aws_security_group" "ecs" {
  name   = "reportcrime-ecs-sg"
  vpc_id = aws_vpc.main.id
  
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Database Security Group
resource "aws_security_group" "db" {
  name   = "reportcrime-db-sg"
  vpc_id = aws_vpc.main.id
  
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
}

# Redis Security Group
resource "aws_security_group" "redis" {
  name   = "reportcrime-redis-sg"
  vpc_id = aws_vpc.main.id
  
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
}
```

### 5. IAM Roles
```hcl
# ECS Task Execution Role
resource "aws_iam_role" "ecs_execution" {
  name = "reportcrime-ecs-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role (app permissions)
resource "aws_iam_role" "ecs_task" {
  name = "reportcrime-ecs-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}
```

## Deliverable Checklist
- [ ] VPC created with proper CIDR
- [ ] 2 public subnets across AZs
- [ ] 2 private subnets across AZs
- [ ] Internet Gateway attached
- [ ] NAT Gateway in public subnet
- [ ] Route tables configured
- [ ] ALB security group (443 inbound)
- [ ] ECS security group (3000 from ALB)
- [ ] DB security group (5432 from ECS)
- [ ] Redis security group (6379 from ECS)
- [ ] ECS execution role created
- [ ] ECS task role created
- [ ] Can deploy test EC2 in private subnet

## Files (4 total)
1. `infrastructure/vpc.tf` - VPC and subnets
2. `infrastructure/security_groups.tf` - Security groups
3. `infrastructure/iam.tf` - IAM roles
4. `infrastructure/variables.tf` - Configurable values
