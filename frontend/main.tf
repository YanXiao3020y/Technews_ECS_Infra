provider "aws" {
  region = "us-east-2"
}

data "terraform_remote_state" "load_balancer" {
  backend = "s3"
  config = {
    bucket = "my-terraform-state-bucket-technews"
    key    = "loadbalancer/terraform.tfstate"
    region = "us-east-2"
  }
}

# data "terraform_remote_state" "load_balancer" {
#   backend = "local"
#   config = { path = "../load_balancer/terraform.tfstate" }
# }

resource "aws_cloudwatch_log_group" "frontend_logs" {
  name              = "/ecs/technews-platform-frontend"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "frontend_task" {
  family                   = "frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.terraform_remote_state.load_balancer.outputs.ecs_task_execution_role_arn

  container_definitions = jsonencode([{
    name  = "technews-platform-frontend"
    image = "087366871540.dkr.ecr.us-east-2.amazonaws.com/technews/frontend:latest"
    portMappings = [{ 
      containerPort = 3000, 
      hostPort = 3000 
      }]
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"        = "/ecs/technews-platform-frontend",
        "awslogs-region"       = "us-east-2",
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}


resource "aws_ecs_service" "frontend" {
  name            = "frontend-service"
  cluster         = data.terraform_remote_state.load_balancer.outputs.ecs_cluster_id

  task_definition = aws_ecs_task_definition.frontend_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = data.terraform_remote_state.load_balancer.outputs.subnets
    security_groups = [data.terraform_remote_state.load_balancer.outputs.alb_security_group]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = data.terraform_remote_state.load_balancer.outputs.frontend_tg_arn
    container_name   = "technews-platform-frontend"
    container_port   = 3000
  }
}
