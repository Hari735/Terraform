terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.0.0"
    }
  }

  
  required_version = "~> 1.5.6"
}

provider "aws" {
  region = var.aws_region
  access_key = "AKIARPBX52J6FR3JUGXY"
  secret_key = "wuI77Q0hZS3BJ5kOYu515NrY4cf/qJqr6X/gvoNK"

}
resource "aws_instance" "ec2_example_with_data_source" {

    ami           = "ami-0261755bbcb8c4a84"
    instance_type =  "t2.micro"

    tags = {
      Name = "Terraform EC2"
    }
}
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "Wayfarer_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  tags = {
    Name = "Wayfarer_vpc"
  }
}

resource "aws_internet_gateway" "Wayfarer_igw" {
  vpc_id = aws_vpc.Wayfarer_vpc.id
  tags = {
    Name = "Wayfarer_igw"
  }
}

resource "aws_subnet" "Wayfarer_public_subnet" {
  count             = var.subnet_count.public
  vpc_id            = aws_vpc.Wayfarer_vpc.id
  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "Wayfarer_public_subnet_${count.index}"
  }
}

// Create a group of private subnets based on the variable subnet_count.private
resource "aws_subnet" "Wayfarer_private_subnet" {
  count             = var.subnet_count.private
   vpc_id            = aws_vpc.Wayfarer_vpc.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "Wayfarer_private_subnet_${count.index}"
  }
}

resource "aws_route_table" "Wayfarer_public_rt" {
  vpc_id = aws_vpc.Wayfarer_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.Wayfarer_igw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = var.subnet_count.public
  route_table_id = aws_route_table.Wayfarer_public_rt.id
  subnet_id      = 	aws_subnet.Wayfarer_public_subnet[count.index].id
}

resource "aws_route_table" "Wayfarer_private_rt" {
  vpc_id = aws_vpc.Wayfarer_vpc.id
  
}

resource "aws_route_table_association" "private" {
  count          = var.subnet_count.private
  route_table_id = aws_route_table.Wayfarer_private_rt.id
  subnet_id      = aws_subnet.Wayfarer_private_subnet[count.index].id
}

resource "aws_security_group" "wayfarer_web_sg" {
  // Basic details like the name and description of the SG
  name        = "wayfarer_web_sg"
  description = "Security group for wayfarer web servers"
  // We want the SG to be in the "wayfarer_vpc" VPC
  vpc_id      = aws_vpc.Wayfarer_vpc.id
  ingress {
    description = "Allow all traffic through HTTP"
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH from my computer"
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    // This is using the variable "my_ip"
    # cidr_blocks = ["${var.my_ip}/24"]
  }

  // This outbound rule is allowing all outbound traffic
  // with the EC2 instances
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Here we are tagging the SG with the name "wayfarer_web_sg"
  tags = {
    Name = "Wayfarer_web_sg"
  }
}

// Create a security group for the RDS instances called "wayfarer_db_sg"
resource "aws_security_group" "Wayfarer_db_sg" {
    name        = "Wayfarer_db_sg"
  description = "Security group for Wayfarer databases"
    vpc_id      = aws_vpc.Wayfarer_vpc.id
  ingress {
    description     = "Allow MySQL traffic from only the web sg"
    from_port       = "3306"
    to_port         = "3306"
    protocol        = "tcp"
    security_groups = [aws_security_group.wayfarer_web_sg.id]
  }

  tags = {
    Name = "wayfarer_db_sg"
  }
}

resource "aws_db_subnet_group" "Wayfarer_db_subnet_group" {
  name        = "wayfarer_db_subnet_group"
  description = "DB subnet group for Wayfarer"
  subnet_ids  = [for subnet in aws_subnet.Wayfarer_private_subnet : subnet.id]
}

resource "aws_db_instance" "Wayfarer_database" {
  allocated_storage      = var.settings.database.allocated_storage
  engine                 = var.settings.database.engine
  engine_version         = var.settings.database.engine_version
  instance_class         = var.settings.database.instance_class
  db_name                = var.settings.database.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.Wayfarer_db_subnet_group.id
  vpc_security_group_ids = [aws_security_group.Wayfarer_db_sg.id]
  skip_final_snapshot    = var.settings.database.skip_final_snapshot
}

resource "aws_key_pair" "Wayfarer_kp" {
  key_name   = "Wayfarer_kp"
  public_key = file("Wayfarer_kp.pub")
}

resource "aws_instance" "Wayfarer_web" {
  count                  = var.settings.web_app.count
  ami                    = "ami-0261755bbcb8c4a84"
  instance_type          = var.settings.web_app.instance_type
  subnet_id              = aws_subnet.Wayfarer_public_subnet[count.index].id
  key_name               = aws_key_pair.Wayfarer_kp.key_name
  vpc_security_group_ids = [aws_security_group.wayfarer_web_sg.id]
  tags = {
    Name = "Wayfarer_web_${count.index}"
  }
}

resource "aws_eip" "Wayfarer_web_eip" {
	count    = var.settings.web_app.count
  instance = aws_instance.Wayfarer_web[count.index].id
  vpc      = true
  tags = {
    Name = "Wayfarer_web_eip_${count.index}"
  }
}
