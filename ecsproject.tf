############### ECS CLUSTER ##############################################################################


resource "aws_ecs_cluster" "wordpress_cluster" {
  name = "wordpress-cluster"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "wordpress" {
  family                   = "wordpress-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = "wordpress:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
      environment = [
        {
          name  = "WORDPRESS_DB_HOST"
          value = aws_db_instance.default.endpoint
        },
        {
          name  = "WORDPRESS_DB_NAME"
          value = "default"
        },
        {
          name  = "WORDPRESS_DB_USER"
          value = "admin"
        },
        {
          name  = "WORDPRESS_DB_PASSWORD"
          value = "password"
        }
      ]
    }
  ])

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn
}





resource "aws_ecs_service" "wordpress" {
  name            = "wordpress-service"
  cluster         = aws_ecs_cluster.wordpress_cluster.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = [aws_subnet.public[0].id, aws_subnet.public[1].id, aws_subnet.public[2].id,]
    security_groups  = [aws_security_group.alb_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.Wordpress_TG.arn
    container_name   = "wordpress"
    container_port   = 80
  }
  #depends_on = [aws_lb_listener.http]
}

################ SUBNETS AND VPC #####################################



resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
}

# Create subnets

resource "aws_subnet" "public" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(var.azs, count.index)
}

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = element(var.azs, count.index)
}


# Cretae internet Gateway

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}


# Create NAT Gateways


resource "aws_nat_gateway" "ngw" {
  count           = 3
  allocation_id   = aws_eip.nat[count.index].id
  subnet_id       = aws_subnet.private[count.index].id
}

resource "aws_eip" "nat" {
  count = 3
}


#Create Route tables

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  count          = 3
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw[count.index].id
  }
  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}




################################## SEC GROUPS ##############################

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.main.id

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






########################### LOADBALANCER ##############################################









resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]       # needt to change
  #subnets            = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
  subnets            = concat(aws_subnet.public[*].id)
  tags = {
    Name = "WordPressALB"
  }
}



resource "aws_lb_listener" "wordpress" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.Wordpress_TG.arn
  }
}


resource "aws_lb_target_group" "Wordpress_TG" {
   name     = "learn-asg-terramino"
   port     = 80
   protocol = "HTTP"
   vpc_id   = aws_vpc.main.id
   target_type = "ip" 
 }






###################################### DB INSTANCE ###############################


resource "aws_db_subnet_group" "default" {
  name        = "ecs-subnet-group"
  description = "Terraform example RDS subnet group"

  subnet_ids  = [aws_subnet.private[0].id, aws_subnet.private[1].id, aws_subnet.private[2].id,]
}

resource "aws_db_instance" "default" {
  allocated_storage    = 10
  db_name              = "db"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql8.0"
  
  
  db_subnet_group_name = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  # db_subnet_group_name = OUR!!! #chaange
  skip_final_snapshot  = true

}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow MySQL inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
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