# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/24"
}

#Subnet publica
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
}

# Tabela de Rota para Subnet Pública
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_subnet_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_route_table.id
}

#Subnet privada
resource "aws_subnet" "private_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.region}a"
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "${var.region}b"
}

# Elastic IP para o NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# NAT Gateway
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_a.id
}

# Tabela de Rotas para Subnet Privada
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "private_nat_access" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

resource "aws_route_table_association" "private_subnet_a" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_b" {
  subnet_id      = aws_subnet.private_subnet_b.id
  route_table_id = aws_route_table.private_route_table.id
}

#Grupo de segurança lambda

resource "aws_security_group" "lambda_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Permitir apenas tráfego interno
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#grupo de segurança banco
resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#DB
resource "aws_db_instance" "banco" {
    allocated_storage    = 270
    engine               = "mysql"
    engine_version       = "8.0"
    instance_class       = "db.t4g.xlarge"
    db_name                 = "bancoChallenge"
    username             = "admin"
    password             = "fiap123"
    db_subnet_group_name = aws_db_subnet_group.db_subnet.id
}

resource "aws_db_subnet_group" "db_subnet" {
    name = "dbsubnet"
    subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  
}



# Lambda
resource "aws_lambda_function" "lambda-function" {
  filename      = "${path.module}/code.zip"
  function_name = "api-gw-lambda"
  role          = aws_iam_role.iam-role.arn
  handler       = "code.lambda_handler"
  runtime       = "python3.9"

  vpc_config {
    subnet_ids         = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.banco.address
      DB_USER     = "admin"
      DB_PASSWORD = "fiap123"
      DB_NAME     = "bancoChallenge"
    }
  }
}

# Função IAM para Lambda
resource "aws_iam_role" "iam-role" {
  name = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Política para Lambda acessar RDS e logs no CloudWatch
resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.iam-role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "rds:*",
          "logs:*",
          "cloudwatch:*"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# API Getway
resource "aws_api_gateway_rest_api" "API"{
    name="api-challenge"
    description="api-challenge"
    endpoint_configuration{
        types = ["REGIONAL"]
    }
}

resource "aws_api_gateway_resource" "Resource" {
    rest_api_id = aws_api_gateway_rest_api.API.id
    parent_id = aws_api_gateway_rest_api.API.root_resource_id
    path_part = "receive-data"
}

resource "aws_api_gateway_method" "Method" {
    rest_api_id = aws_api_gateway_rest_api.API.id
    resource_id = aws_api_gateway_resource.Resource.id
    http_method = "POST"
    authorization = "NONE"
  
}

resource "aws_api_gateway_integration" "Integration" {
  rest_api_id             = aws_api_gateway_rest_api.API.id
  resource_id             = aws_api_gateway_resource.Resource.id
  http_method             = aws_api_gateway_method.Method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda-function.invoke_arn
}


resource "aws_lambda_permission" "apigw-lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda-function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.AWS_ACCOUNT_ID}:${aws_api_gateway_rest_api.API.id}/*/${aws_api_gateway_method.Method.http_method}${aws_api_gateway_resource.Resource.path}"
}


resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.API.id
  resource_id = aws_api_gateway_resource.Resource.id
  http_method = aws_api_gateway_method.Method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"=true,
    "method.response.header.Access-Control-Allow-Methods"=true,
    "method.response.header.Access-Control-Allow-Origin"=true
  }
}

resource "aws_api_gateway_integration_response" "Integration-Response" {
  rest_api_id = aws_api_gateway_rest_api.API.id
  resource_id = aws_api_gateway_resource.Resource.id
  http_method = aws_api_gateway_method.Method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" =  "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  response_templates = {
    "application/json" = jsonencode({"LambdaValue"="$input.path('$').body", "data"="Custom Value"})
  }

  depends_on = [
    aws_api_gateway_integration.Integration
  ]

}

resource "aws_api_gateway_deployment" "example" {
  depends_on = [
    aws_api_gateway_integration.Integration
  ]
  rest_api_id = aws_api_gateway_rest_api.API.id
  stage_name  = "Challenge"
}



