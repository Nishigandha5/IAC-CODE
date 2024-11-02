provider "aws" {
    region = "us-east-1"
}

resource "aws_security_group" "sg_vault" {
    name = "sg_vault"
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}
  

resource "aws_instance" "ec2_vault" {
    ami = "ami-0b0dcb5067f052a63"
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.sg_vault.id]
    tags = {
        Name = "vault"
    }
    key_name = "AWS_k"
}



output "instance_public_ip" {
  value = aws_instance.ec2_vault.public_ip
  description = "The public IP of the EC2 instance"
}
