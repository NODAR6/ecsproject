resource "aws_ecs_cluster" "foo" {
  name = "ecsnodar"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "wordpress_service" {
  family = "wordpress-service"  # Renamed the task definition for clarity

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = "nodarogbaidze/wordpress"
      cpu       = 10
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    },
  ])

  volume {
    name      = "service-storage"
    host_path = "/ecs/service-storage"
  }

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in [us-east-1a, us-east-1b]"
  }
}

resource "aws_s3_bucket" "example" {
  bucket = "nodar-ecs-bucket"  

  tags = {
    Name        = "nodar-ecs"
    Environment = "Dev"
  }
}






