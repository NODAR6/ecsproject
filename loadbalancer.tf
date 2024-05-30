resource "aws_lb" "test" {
  name               = "lb-ecs"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["ecs-sec-group"]  # Replace 'ecs-sec-group' with actual security group ID
  subnets            = [aws_subnet.subnet_01.id]    # Replace 'subnet-01cce6abe32093362' with actual subnet ID

  enable_deletion_protection = true

  # access_logs {
  #   bucket  = aws_s3_bucket.lb_logs.id
  #   prefix  = "test-lb"
  #   enabled = true
  # }

  # tags = {
  #   Environment = "production"
  # }
}

resource "aws_lb_listener" "wordpress" {
  load_balancer_arn = aws_lb.test.arn  # Corrected the reference to the load balancer
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "your-vpc-id"  # Replace with actual VPC ID

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "wordpress" {
  target_group_arn = aws_lb_target_group.wordpress.arn
  target_id        = "your-ecs-service-id"  # Replace with actual ECS service ID
}

resource "aws_db_instance" "wordpress" {
  allocated_storage    = 10
  db_name              = "mydb"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.micro"
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
}
