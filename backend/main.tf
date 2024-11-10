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

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/technews-platform-api"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "main" {
  family                   = "main-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.terraform_remote_state.load_balancer.outputs.ecs_task_execution_role_arn

  container_definitions = jsonencode([{
    name  = "technews-platform-api"
    image = "087366871540.dkr.ecr.us-east-2.amazonaws.com/technews/backend:latest"
    portMappings = [{ 
      containerPort = 5001, 
      hostPort = 5001 
      }]
    environment = [{ 
      name = "MONGO_URI", 
      value = "mongodb+srv://wangaus1997:technews2024@cluster0.wgtmm.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0" 
      }]
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"        = "/ecs/technews-platform-api",
        "awslogs-region"       = "us-east-2",
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "main" {
  name            = "main-service"
  cluster         = data.terraform_remote_state.load_balancer.outputs.ecs_cluster_id

  task_definition = aws_ecs_task_definition.main.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = data.terraform_remote_state.load_balancer.outputs.subnets
    security_groups = [data.terraform_remote_state.load_balancer.outputs.alb_security_group]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = data.terraform_remote_state.load_balancer.outputs.backend_tg_arn
    container_name   = "technews-platform-api"
    container_port   = 5001
  }

  lifecycle {
    prevent_destroy = false  # Allow immediate destruction without waiting
  }

  # Remove the load balancer from the ECS service creation/destroy sequence
  depends_on = []  # No dependency on load balancer here

}
