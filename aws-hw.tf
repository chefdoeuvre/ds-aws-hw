terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 2.70"
    }
    mysql = {
      source  = "winebarrel/mysql"
      version = "1.9.0-p6"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "eu-west-2"
}

#==================================================================================  VPC

resource "aws_vpc" "hw_vpc" {
  cidr_block = "172.16.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "hw-vpc"
  }
}

#==================================================================================  Subnets

resource "aws_subnet" "hw_subnet1" {
  vpc_id                  = aws_vpc.hw_vpc.id
  cidr_block              = "172.16.10.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "hw-subnet10"
  }
}

resource "aws_subnet" "hw_subnet2" {
  vpc_id                  = aws_vpc.hw_vpc.id
  cidr_block              = "172.16.20.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "hw-subnet20"
  }
}

#==================================================================================  IG

resource "aws_internet_gateway" "hw_gw" {
  vpc_id = aws_vpc.hw_vpc.id

  tags = {
    Name = "hw_gw"
  }
}

#==================================================================================  ROUTE

resource "aws_route_table" "hw_route" {
  vpc_id = aws_vpc.hw_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hw_gw.id
  }

  tags = {
    Name = "hw_route"
  }
}

resource "aws_route_table_association" "hw-r-s-a1" {
  subnet_id      = aws_subnet.hw_subnet1.id
  route_table_id = aws_route_table.hw_route.id
}

resource "aws_route_table_association" "hw-r-s-a2" {
  subnet_id      = aws_subnet.hw_subnet2.id
  route_table_id = aws_route_table.hw_route.id
}

#==================================================================================  Security Groups

resource "aws_security_group" "allow_http" { # and ssh for test
  name        = "allow_http"
  description = "Allow http inbound traffic"
  vpc_id      = aws_vpc.hw_vpc.id
  ingress {
    description = "HTTP Access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow_http"
  }
}

resource "aws_security_group" "allow_3306" {
  name        = "allow_3306"
  description = "Allow 3306 inbound traffic"
  vpc_id      = aws_vpc.hw_vpc.id

  ingress {
    description = "To database"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.hw_vpc.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_3306"
  }
}

resource "aws_security_group" "allow_EFS" {
  name        = "allow_EFS"
  description = "allow_EFS  inbound traffic"
  vpc_id      = aws_vpc.hw_vpc.id

  ingress {
    description = "allow_EFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.hw_vpc.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_EFS"
  }
}

#==================================================================================  elb
## Migrate to alb?

resource "aws_elb" "hw_elb" {
  name            = "hw-elb"
  security_groups = [aws_security_group.allow_http.id]
  subnets         = [aws_subnet.hw_subnet1.id, aws_subnet.hw_subnet2.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                   = [aws_instance.WSN1.id, aws_instance.WSN2.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "hw-elb"
  }
}

#==================================================================================  EFS for servers
# Wordpress should keep media files on mounted EFS

resource "aws_efs_mount_target" "hw_efs_mount1" {
  file_system_id = aws_efs_file_system.hw_efs.id
  subnet_id      = aws_subnet.hw_subnet1.id
  security_groups = [aws_security_group.allow_EFS.id]
}

resource "aws_efs_mount_target" "hw_efs_mount2" {
  file_system_id = aws_efs_file_system.hw_efs.id
  subnet_id      = aws_subnet.hw_subnet2.id
  security_groups = [aws_security_group.allow_EFS.id]
}

resource "aws_efs_file_system" "hw_efs" {
  creation_token = "hw-efs"

  tags = {
    Name = "hw-efs"
  }
}

#================================================================================== MYSQL for WordPress

resource "aws_db_subnet_group" "hw_db_subnet_group" {
  name       = "hw_db_subnet_group"
  subnet_ids = [aws_subnet.hw_subnet1.id, aws_subnet.hw_subnet2.id]

  tags = {
    Name = "HW DB subnet group"
  }
}

resource "aws_db_instance" "hw_msql" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  name                   = "wordpress"
  username               = "username"
  password               = "Passw0rd"
  parameter_group_name   = "default.mysql5.7"
  skip_final_snapshot    = "true"
  db_subnet_group_name   = aws_db_subnet_group.hw_db_subnet_group.id
  vpc_security_group_ids = [aws_security_group.allow_3306.id]
}


#================================================================================== TEMPLATE FILE

data "template_file" "init" {
  template = file("install_wordpress.sh.tpl")

  vars = {
    db_host = aws_db_instance.hw_msql.endpoint
    efs_dns = aws_efs_file_system.hw_efs.dns_name
  }
}

#================================================================================== instances


resource "aws_instance" "WSN1" {
  ami             = "ami-0ff4c8fb495a5a50d" # ubuntu
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.hw_subnet1.id
  security_groups = [aws_security_group.allow_http.id]
  tags = {
    Name = "Wordpress Server number 1"
  }
  user_data = data.template_file.init.rendered
}

resource "aws_instance" "WSN2" {
  ami             = "ami-0ff4c8fb495a5a50d" # ubuntu
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.hw_subnet2.id
  security_groups = [aws_security_group.allow_http.id]
  tags = {
    Name = "Wordpress Server number 2"
  }
  user_data = data.template_file.init.rendered
}

#================================================================================== OUTPUT

output "YOUR_LINK" {
  value = aws_elb.hw_elb.dns_name
}
