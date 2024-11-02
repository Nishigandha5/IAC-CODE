provider "aws" {
  region = "us-east-1"  
}

resource "aws_vpc" "vpc_proj" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "vpc_proj"
  }
}

# Public Subnets
resource "aws_subnet" "subnet_proj_pub2" {
  vpc_id            = aws_vpc.vpc_proj.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "subnet_proj_public2"
  }
}

resource "aws_subnet" "subnet_proj_public" {
  vpc_id            = aws_vpc.vpc_proj.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "subnet_proj_public"
  }
}

# Private Subnets
resource "aws_subnet" "priv_sub" {
  vpc_id            = aws_vpc.vpc_proj.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "priv_sub"
  }
}

resource "aws_subnet" "priv_sub2" {
  vpc_id            = aws_vpc.vpc_proj.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "priv_sub2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw_proj" {
  vpc_id = aws_vpc.vpc_proj.id
  tags = {
    Name = "igw_proj"
  }
}

# Elastic IPs for NAT Gateways - static ip address it cannot be change
#The vpc argument in aws_eip has been deprecated and 
#should be replaced with the domain attribute. 
#You can set domain = "vpc" 
#to specify that the Elastic IP is for a VPC.


resource "aws_eip" "eip_proj" {
  domain = "vpc"
  tags = {
    Name = "eip_proj"
  }
}

resource "aws_eip" "eip_proj2" {
  domain = "vpc"
  tags = {
    Name = "eip_proj2"
  }
}

# NAT Gateways
resource "aws_nat_gateway" "nat_proj" {
  subnet_id     = aws_subnet.subnet_proj_public.id
  allocation_id = aws_eip.eip_proj.id
  tags = {
    Name = "nat_proj"
  }
}

resource "aws_nat_gateway" "nat_proj2" {
  subnet_id     = aws_subnet.subnet_proj_pub2.id
  allocation_id = aws_eip.eip_proj2.id
  tags = {
    Name = "nat_proj2"
  }
}

# Public Route Table and Associations
resource "aws_route_table" "rt_proj" {
  vpc_id = aws_vpc.vpc_proj.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_proj.id
  }
  tags = {
    Name = "rt_proj"
  }
}

resource "aws_route_table_association" "rta_proj" {
  subnet_id      = aws_subnet.subnet_proj_public.id
  route_table_id = aws_route_table.rt_proj.id
}

resource "aws_route_table_association" "rta_proj2" {
  subnet_id      = aws_subnet.subnet_proj_pub2.id
  route_table_id = aws_route_table.rt_proj.id
}

# Private Route Tables and Associations
resource "aws_route_table" "priv_rt" {
  vpc_id = aws_vpc.vpc_proj.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_proj.id
  }
  tags = {
    Name = "priv_rt1"
  }
}

resource "aws_route_table" "priv_rt2" {
  vpc_id = aws_vpc.vpc_proj.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_proj2.id
  }
  tags = {
    Name = "priv_rt2"
  }
}

resource "aws_route_table_association" "priv_rta" {
  subnet_id      = aws_subnet.priv_sub.id
  route_table_id = aws_route_table.priv_rt.id
}

resource "aws_route_table_association" "priv_rta2" {
  subnet_id      = aws_subnet.priv_sub2.id
  route_table_id = aws_route_table.priv_rt2.id
}
# Security Group
resource "aws_security_group" "sg_proj" {
  name_prefix = "sg_proj"
  vpc_id      = aws_vpc.vpc_proj.id

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
# Launch Configuration
/*resource "aws_launch_configuration" "LC_pp" {
    name = "LC_pp"
    image_id = "ami-0b0dcb5067f052a63"
    instance_type = "t2.micro"
    key_name = "AWS_k"
    security_groups = [aws_security_group.sg_proj.id]
    associate_public_ip_address = true
} */


# aws_launch_template
resource "aws_launch_template" "LT_pp" {
    name = "LT_pp"
    image_id = "ami-0b0dcb5067f052a63"
    instance_type = "t2.micro"
    key_name = "AWS_k"
    vpc_security_group_ids = [aws_security_group.sg_proj.id]
}




# autoscaling
resource "aws_autoscaling_group" "ASG_pp" {
    name = "ASG_pp"
    launch_template {
        id = aws_launch_template.LT_pp.id
        version = "$Latest"
    }
    max_size = 2
    min_size = 1
    desired_capacity = 2
    #launch_configuration = aws_launch_configuration.LC_pp.name
    vpc_zone_identifier = [aws_subnet.priv_sub.id, aws_subnet.priv_sub2.id]
    #target_group_arns = [aws_lb_target_group.tg_pp.arn]
    tag {
        key = "Name"
        value = "ASG_pp"
        propagate_at_launch = true #This ensures all launched instances are tagged with "Name = autoscaling_group_instance" This is especially useful for tracking, managing, and organizing instances in larger cloud environments.
    }
    /*
    lifecycle {
        create_before_destroy = true
    }
    depends_on = [aws_nat_gateway.nat_proj, aws_nat_gateway.nat_proj2]
    */
    #health_check_type = "EC2" #This is the default value and is optional.
    #health_check_grace_period = 300 #This is the default value and is optional.
    #termination_policies = ["OldestInstance"]
}

/* after implenting above iac there instnces will not have public ip - bcoz In your Auto Scaling Group configuration, the instances are being created in the **private subnets** (`priv_sub` and `priv_sub2`), which don't automatically assign public IP addresses to instances. To assign public IP addresses, you should either:

1. **Use Public Subnets in `vpc_zone_identifier`** if you want instances to have public IPs.
2. **Explicitly set `associate_public_ip_address` in the Launch Template**, which will assign a public IP to each instance regardless of the subnet type.

### Solution 1: Use Public Subnets
If your instances need direct internet access, change the subnets in `vpc_zone_identifier` to the public subnets:

```hcl
vpc_zone_identifier = [aws_subnet.subnet_proj_public.id, aws_subnet.subnet_proj_pub2.id]
```

### Solution 2: Associate Public IP in Launch Template
If you want to keep the instances in private subnets but still require them to have a public IP, you can update your Launch Template to include the `associate_public_ip_address` attribute as follows:

```hcl
resource "aws_launch_template" "LT_pp" {
    name                      = "LT_pp"
    image_id                  = "ami-0b0dcb5067f052a63"
    instance_type             = "t2.micro"
    key_name                  = "AWS_k"
    vpc_security_group_ids    = [aws_security_group.sg_proj.id]
    network_interfaces {
        associate_public_ip_address = true
    }
}
```

This configuration will assign a public IP to each 
instance launched in the Auto Scaling Group, regardless of the subnet type.
*/

resource "aws_security_group" "bastion_sg" {
    name = "bastion_sg"
    vpc_id = aws_vpc.vpc_proj.id
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
resource "aws_instance" "bastion_ec2" {
  ami = "ami-0b0dcb5067f052a63"
  instance_type = "t2.micro"
  key_name = "AWS_k"
  #vpc_security_group_ids = [aws_security_group.sg_proj.id]
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  subnet_id = aws_subnet.subnet_proj_public.id
  associate_public_ip_address = true
  tags = {
    Name = "bastion_ec2"
  }
}



output "instance_public_ip" {
  value = aws_instance.bastion_ec2.public_ip
  description = "The public IP of the EC2 instance"
}

/* adding this cmd (secure coping)bcpz , we neeed to add key pair to bastion host instance , so afterthatwe can connect tto private instances 
and then can access the private instances -
here we are copying key pair from personal to bastion host instance
#scp -i /Users/thorins/documents/AWS_k.pem /Users/thorins/documents/AWS_k.pem ec2-user@18.207.96.109:/home/ec2-user
ssh -i AWS_k.pem ec2-user@18.207.96.109 to check that key pair is in instance
to get login asg_pp autoscaling instance
ssh -i AWS_k.pem ec2-user@10.0.135.87-- private ip addr instance
and install python application on private ipp instances
<!DOCTYPE html>
<html>
<body>

<h1>My First Heading</h1>
<p>My first paragraph.</p>

</body>
</html>

python3 -m http.server 8000
now creating load balancer




resource "null_resource" "ssh_commands" {
  provisioner "local-exec" {
    command = <<EOT
      # Copy the SSH key to the bastion host
      scp -i ${path.cwd}/AWS_k.pem ${path.cwd}/AWS_k.pem ec2-user@${aws_instance.bastion_ec2.public_ip}:~/

      # SSH into the bastion host
      ssh -i ${path.cwd}/AWS_k.pem ec2-user@${aws_instance.bastion_ec2.public_ip} << 'EOF'
        # Fetch the private IP of the instance created by the Auto Scaling Group
        PRIVATE_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=ASG_pp" --query "Reservations[].Instances[].PrivateIpAddress" --output text)

        # SSH into the private instance using its private IP
        ssh -i ${path.cwd}/AWS_k.pem ec2-user@${PRIVATE_IP}
      EOF
    EOT
    interpreter = ["bash", "-c"]
    on_failure = continue
  }
  depends_on = [aws_instance.bastion_ec2] #depends_on attribute is used at the resource level for null_resource "ssh_commands", ensuring that the SSH commands are executed only after the aws_instance.bastion_ec2 resource is created. The depends_on attribute has been removed from the provisioner block where it was not supported.
}*/



/*
# Provisioner to execute commands after instance creation
  provisioner "local-exec" {
    command = "scp -i ${path.cwd}/AWS_k.pem ${path.cwd}/AWS_k.pem ec2-user@${aws_instance.bastion_ec2.public_ip}:~/"
    interpreter = ["bash", "-c"]
    on_failure = continue
    depends_on = [aws_instance.bastion_ec2]
    connection {
        type = "ssh"
        user = "XXXXXXXX"
        private_key = file("${path.cwd}/AWS_k.pem")
        host = aws_instance.bastion_ec2.public_ip
        timeout = "5m"
        agent = false
        #script_path = "~/AWS_k.pem"
    }
  }
resource "null_resource" "ssh_to_private_instance" {
  provisioner "local-exec" {
    command = <<EOT
      # Read the private IP from the temporary file created earlier
      PRIVATE_IP=$(cat /tmp/private_ip.txt)
      # SSH into the private instance
      ssh -i ${path.cwd}/AWS_k.pem ec2-user@$PRIVATE_IP
    EOT
  }

  # Ensure this runs after the private IP is fetched
  depends_on = [null_resource.get_private_ip]
}
*/
#----------------------------------------------------------------------
# Declare the variable for the PEM file path
variable "pem_file_path" {
  description = "Path to the PEM file"
  default     = "/Users/thorins/documents/AWS_k.pem"
}

# Resource to fetch private IP
resource "null_resource" "get_private_ip" {
  provisioner "remote-exec" {
    inline = [
      # Fetch the private IP of the instance created by the Auto Scaling Group
      "PRIVATE_IP=$(aws ec2 describe-instances --filters 'Name=tag:Name,Values=ASG_pp' --query 'Reservations[].Instances[].PrivateIpAddress' --output text)",
      # Store the private IP in a file
      "echo $PRIVATE_IP > /prod_proj/private_ip.txt",
      "echo 'Private IP fetched: $PRIVATE_IP'"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"  # Replace with your SSH user
      private_key = file(var.pem_file_path)
      host        = aws_instance.bastion_ec2.public_ip
      timeout     = "5m"
      agent       = false
    }
  }

  # Ensure this runs after the bastion instance is created
  depends_on = [aws_instance.bastion_ec2]
}

# Resource to SSH into the private instance
resource "null_resource" "ssh_to_private_instance" {
  provisioner "local-exec" {
  command = <<EOT
    # Read the private IP from the temporary file created earlier
    PRIVATE_IP=$(cat /tmp/private_ip.txt)
    # SSH into the private instance with a timeout
    ssh -o ConnectTimeout=10 -i ${var.pem_file_path} ec2-user@$PRIVATE_IP || echo "SSH failed"
    else echo "Private IP file does not exist."
      fi
  EOT
}
  # Ensure this runs after the private IP is fetched
  depends_on = [null_resource.get_private_ip]
}


resource "aws_lb" "lb_proj" {
    name = "lb-proj"
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.sg_proj.id]
    subnets = [aws_subnet.subnet_proj_public.id, aws_subnet.subnet_proj_pub2.id]

}


resource "aws_lb_target_group" "tg_pp" {
    name = "tg-pp"
    port = 80
    protocol = "HTTP"
    vpc_id = aws_vpc.vpc_proj.id
    health_check {
        path = "/"
        protocol = "HTTP"
        port = 80
        healthy_threshold = 2
        unhealthy_threshold = 2
        timeout = 3
        interval = 5
        matcher = "200"
    }
  
}


resource "aws_lb_listener" "listener_proj" {
    load_balancer_arn = aws_lb.lb_proj.arn
    port = 80
    protocol = "HTTP"
    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.tg_pp.arn
    }
  
}
/* Data source to dynamically fetch instance IDs by tag
1. Check Data Source Filters
Make sure that the data "aws_instances" data source filter is correctly set up to capture instances from the Auto Scaling Group. For example, ensure that you’re filtering by the tag or criteria that matches your Auto Scaling Group's instances.
*/

/*Add a Dependency on the Auto Scaling Group
Ensure that data "aws_instances" depends on the creation of the Auto Scaling Group, so Terraform waits until the instances are launched.
Add depends_on to the data "aws_instances" block:
*/

# Define a static map for instance IDs with placeholder values
locals {
  instance_map = {
    "instance_1" = null  # Placeholder, to be assigned at apply-time if instance is available
    "instance_2" = null
  }
}

# Fetch the instance IDs after ASG instances are created
data "aws_instances" "asg_instances" {
  depends_on = [aws_autoscaling_group.ASG_pp]

  filter {
    name   = "tag:Name"
    values = ["ASG_pp"]
  }
}

# Define instance_map with static keys and assign apply-time values where possible
locals {
  instance_mapp = {

    "instance_1" = length(data.aws_instances.asg_instances.ids) > 0 ? data.aws_instances.asg_instances.ids[0] : null
    "instance_2" = length(data.aws_instances.asg_instances.ids) > 1 ? data.aws_instances.asg_instances.ids[1] : null
  }
}

resource "aws_lb_target_group_attachment" "tg_attach_pp" {
  for_each         = toset(data.aws_instances.asg_instances.ids)
  #{ for k, v in local.instance_map : k => v if v != null }  # Iterates only over non-null values
  target_group_arn = aws_lb_target_group.tg_pp.arn
  target_id        = each.value
  port             = 80
}
