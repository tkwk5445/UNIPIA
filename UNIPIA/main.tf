
# VPC 리소스 정의
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"
  tags = {
    Name = "dev-smbm-vpc"
  }
}

# Public 서브넷 정의
resource "aws_subnet" "public" {
  count             = length(var.public_subnet)
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.public_subnet[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    Name = "dev-smbm-public-subnet${var.azs1[count.index]}"
  }
}
# Private 서브넷 정의
resource "aws_subnet" "private" {
  count             = length(var.private_subnet)
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_subnet[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    Name = "dev-smbm-private-subnet${var.azs1[count.index]}"
  }
}

# Internet Gateway 리소스 정의
resource "aws_internet_gateway" "vpc_igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "dev-smbm-igw"
  }
}

# Elastic IP 리소스 정의
resource "aws_eip" "eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.vpc_igw]
  tags = {
    Name = "dev-smbm-eip"
  }
  lifecycle {
    create_before_destroy = true
  }
}

# NAT Gateway 리소스 정의
resource "aws_nat_gateway" "public_nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.vpc_igw]
  tags = {
    Name = "dev-smbm-nat"
  }
}

# Public 서브넷에 대한 기본 라우팅 테이블 정의
resource "aws_default_route_table" "public_rt" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpc_igw.id
  }
  tags = {
    Name = "dev-smbm-public-rt"
  }
}

# Public 서브넷과 기본 라우팅 테이블의 연결 정의
resource "aws_route_table_association" "public_rta" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_default_route_table.public_rt.id
}

# Private 서브넷에 대한 라우팅 테이블 정의
resource "aws_route_table" "private_rt" {
  count  = length(var.azs)
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "dev-smbm-private-rt${count.index + 1}"
  }
}

# Private 서브넷과 라우팅 테이블의 연결 정의
resource "aws_route_table_association" "private_rta" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rt[count.index].id
}

# Private 서브넷에 대한 NAT Gateway에 대한 라우팅 정의
resource "aws_route" "private_nat" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.private_rt[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.public_nat.id
}

// Security groups
resource "aws_security_group" "web" {
  name        = "dev-smbm-web-sg"
  description = "accept all ports"
  vpc_id      = aws_vpc.vpc.id
  // 인바운드 규칙: 모든 트래픽 허용
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // 모든 프로토콜 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  // 아웃바운드 규칙: 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // 모든 프로토콜 허용
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "dev-smbm-web-sg"
  }
}

resource "aws_security_group" "was" {
  name        = "dev-smbm-was-sg"
  description = "accept all ports"
  vpc_id      = aws_vpc.vpc.id

  // 인바운드 규칙: 모든 트래픽 허용
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // 모든 프로토콜 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  // 아웃바운드 규칙: 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // 모든 프로토콜 허용
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "dev-smbm-was-sg"
  }
}

// EC2 Instance (ubuntu)
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.image_id
  instance_type               = "t2.micro"
  key_name                    = var.key
  vpc_security_group_ids      = [aws_security_group.web.id]
  subnet_id                   = aws_subnet.public[0].id
  availability_zone           = "ap-northeast-2a"
  associate_public_ip_address = true
  tags = {
    Name = "dev-smbm-web"
  }
}

resource "aws_instance" "was" {
  ami                         = data.aws_ami.ubuntu.image_id
  instance_type               = "t2.small"
  key_name                    = var.key
  vpc_security_group_ids      = [aws_security_group.was.id]
  subnet_id                   = aws_subnet.private[0].id
  availability_zone           = "ap-northeast-2a"
  associate_public_ip_address = false
  tags = {
    Name = "dev-smbm-was"
  }
}

// Target group (web)
/* resource "aws_lb_target_group" "web-tg" {
  name     = "dev-smbm-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
} */

// Target group (was)
resource "aws_lb_target_group" "was-tg" {
  name     = "dev-smbm-was-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  health_check {
    path                = "/api/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

// Target attach (web)
/* resource "aws_lb_target_group_attachment" "web-tg-attach" {
  target_group_arn = aws_lb_target_group.web-tg.arn
  target_id        = aws_instance.web.id
  port             = 80
}
 */
// Target attach (was)
resource "aws_lb_target_group_attachment" "was-tg-attach" {
  target_group_arn = aws_lb_target_group.was-tg.arn
  target_id        = aws_instance.was.id
  port             = 80
}

// EX LoadBalancer (Application)
/* resource "aws_lb" "web-lb" {
  name               = "dev-smbm-ex-alb"
  load_balancer_type = "application"
  subnets = [
    aws_subnet.public[0].id,
    aws_subnet.public[1].id
  ]
  security_groups = [aws_security_group.web.id]
} */

# HTTP Listener for IN LB
/* resource "aws_lb_listener" "web-http" {
  load_balancer_arn = aws_lb.web-lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web-tg.arn
  }
} */

// EX LoadBalancer (Application)
resource "aws_lb" "was-lb" {
  name               = "dev-smbm-was-alb"
  load_balancer_type = "application"
  subnets = [
    aws_subnet.public[0].id,
    aws_subnet.public[1].id
  ]
  security_groups = [aws_security_group.was.id]
}

# HTTP Listener for IN LB
resource "aws_lb_listener" "was-http" {
  load_balancer_arn = aws_lb.was-lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.was-tg.arn
  }
}
