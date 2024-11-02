# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "ec2_nI" {
    instance_type = "t2.micro"
    ami = "ami-0b5eea76982371e91"
    availability_zone = "us-east-1a"
    subnet_id = "subnet-0ec1a50b633fc34bc"
    vpc_security_group_ids = [aws_security_group.sg_ab.id]
    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install httpd -y
                service httpd start
                chkconfig httpd on
                IP_ADDR=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
                echo "Manual instance with IP $IP_ADDR" > /var/www/html/index.html
                echo "ok" > /var/www/html/health.html
                EOF
                
    tags = {
        Name = "ec2_nI"
    }  
}

resource "aws_instance" "ec2_nII" {
    instance_type = "t2.micro"
    ami = "ami-0b5eea76982371e91"
    availability_zone = "us-east-1b"
    subnet_id = "subnet-0610c9a230ccb5054"
    vpc_security_group_ids = [aws_security_group.sg_ab.id]
    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install httpd -y
                service httpd start
                chkconfig httpd on
                IP_ADDR=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
                echo "Manual instance with IP $IP_ADDR" > /var/www/html/index.html
                echo "ok" > /var/www/html/health.html
                EOF
    tags = {
        Name = "ec2_nII"
    }  
}

# Fetch the default VPC (AWS provides this in each region)

data "aws_vpc" "default" {
  default = true
}

# Fetch all default subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


resource "aws_security_group" "sg_ab" {
  description = "openingportsforSSHandHTTP"
  vpc_id = data.aws_vpc.default.id
  tags = {
    Name = "sg_abserver"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
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

# Create a Target Group
resource "aws_lb_target_group" "my_target_group" {
  name     = "my-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id # Set this to your VPC ID

  health_check {
    path                = "/health.html"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Attach the first EC2 instance to the Target Group
resource "aws_lb_target_group_attachment" "tg_attachment_ec2_nI" {
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = aws_instance.ec2_nI.id
  port             = 80
}

# Attach the second EC2 instance to the Target Group
resource "aws_lb_target_group_attachment" "tg_attachment_ec2_nII" {
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = aws_instance.ec2_nII.id
  port             = 80
}


resource "aws_lb" "My-ALB" {
  name               = "My-ALB-tf"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_ab.id]  # Corrected attribute
  subnets            = data.aws_subnets.default.ids  # Automatically fetch all subnets in the default VPC
  tags = {
    Name = "My-ALB"
  }
}
# Create a listener for the ALB
resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.My-ALB.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

#aws ec2 describe-security-groups --query "SecurityGroups[*].{ID:GroupId,Name:GroupName}" --output table

#aws ec2 revoke-security-group-ingress --group-id sg-05e8fc0c10c7109f1 --protocol tcp --port 80 --cidr 54.172.177.113/32
#aws ec2 describe-security-groups --group-ids sg-05e8fc0c10c7109f1  --output json
