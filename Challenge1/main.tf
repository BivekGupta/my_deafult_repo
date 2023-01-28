#Layer 1 - It contaions the public facing ELB, and bastion host in public subnets

resource "aws_security_group" "bastion-sg" {
  name   = "bastion-security-group"
  vpc_id = "aws_vpc.My_VPC.id"

  ingress {
    protocol    = var.bastion_ingress_protocol
    from_port   = var.bastion_ingress_from_port
    to_port     = var.bastion_ingress_to_port
    cidr_blocks = var.bastion_ingress_cidr
  }

  egress {
    protocol    = var.bastion_egress_protocol
    from_port   = var.bastion_egress_from_port
    to_port     = var.bastion_egress_to_port
    cidr_blocks = var.bastion_egress_cidr
  }
}

resource "aws_instance" "bastion" {
  ami                         = var.bastion_ami
  key_name                    = var.key
  instance_type               = var.bastion_instance_type
  security_groups             = [aws_security_group.bastion-sg.id]
  associate_public_ip_address = true
  availability_zone           = data.aws_availability_zones.available.names[0]
}

# Create a new load balancer

resource "aws_elb" "tier-1-elb" {
  name               = "tier1-terraform-elb"
  availability_zone  = data.aws_availability_zones.available.names[0]
  depends_on         = aws_instance.application_server.id

  access_logs {
    bucket        = "logs_bucket"
    bucket_prefix = "elb"
    interval      = 60
  }

  listener {
    instance_port     = 8000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 8000
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/certName"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8000/"
    interval            = 30
  }

  instances                   = [aws_instance.application_server.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "tier1-terraform-elb"
  }
}

#Layer 1 - It contaions the application host in private subnets alongwith autoscaling policy for ec2 instance

resource "aws_security_group" "application-sg" {
  name   = "bastion-security-group"
  vpc_id = "aws_vpc.My_VPC.id"

  ingress {
    protocol    = var.bastion_ingress_protocol
    from_port   = var.bastion_ingress_from_port
    to_port     = var.bastion_ingress_to_port
    cidr_blocks = var.bastion_ingress_cidr
  }

  egress {
    protocol    = var.bastion_egress_protocol
    from_port   = var.bastion_egress_from_port
    to_port     = var.bastion_egress_to_port
    cidr_blocks = var.bastion_egress_cidr
  }
}

resource "aws_instance" "application_server" {
  ami                         = var.application_ami
  key_name                    = var.key
  instance_type               = var.application_instance_type
  security_groups             = [aws_security_group.application-sg.id]
  associate_public_ip_address = true
  availability_zone           = data.aws_availability_zones.available.names[0]
}


resource "aws_placement_group" "auto-scaling" {
  name     = "test"
  strategy = "cluster"
}

resource "aws_autoscaling_group" "my_autoscaling" {
  name                      = "autoscaling-terraform-tier2"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 4
  force_delete              = true
  placement_group           = aws_placement_group.auto-scaling.id
  launch_configuration      = aws_launch_configuration.autoscaling.name
  vpc_zone_identifier       = [data.aws_subnet.example1.id]

  initial_lifecycle_hook {
    name                 = "autoscaling"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 2000
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    notification_target_arn = var.notification_target_arn 
    role_arn                = var.role_arn                

  tag {
    key                 = "type"
    value               = "my_autoscaling"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }

  tag {
    key                 = "scaling-type"
    value               = "target-based"
    propagate_at_launch = false
  }
}

#Layer 3 - It contaions the databases

resource "aws_db_instance" "default" {
  allocated_storage    = 10
  db_name              = "mydb"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  username             = lookup(aws/secretmanager, "username")
  password             = lookup(aws/secretmanager, "password")
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  vpc_security_group_ids = [var.aws_security_group.database-sg.id]
}
