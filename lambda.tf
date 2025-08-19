resource "aws_iam_role" "lambda_role" {
  name = "rotate_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_security_group" "lambda_sg" {
  name   = "rotate-lambda-sg"
  vpc_id = aws_vpc.minimal.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rotate-lambda-sg"
  }
}

resource "aws_lambda_function" "private_lambda" {
  # The Lambda will be built with Maven; the shaded JAR will be at lambda/target/lambda.jar
  # Update the handler below if your handler class changes.
  filename         = "${path.module}/lambda/target/lambda.jar"
  function_name    = "rotate-private-lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "com.example.Handler::handleRequest"
  runtime          = "java11"
  source_code_hash = filebase64sha256("${path.module}/lambda/target/lambda.jar")
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  depends_on = [null_resource.maven_build]
}

resource "null_resource" "maven_build" {
  provisioner "local-exec" {
    command = "mvn -f ${path.module}/lambda/pom.xml clean package -DskipTests"
  }

  triggers = {
    pom       = filesha256("${path.module}/lambda/pom.xml")
    sources   = sha1(join("|", sort(fileset("${path.module}/lambda/src/main/java", "**/*.java"))))
  }

  depends_on = [aws_iam_role.lambda_role]
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.private_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  depends_on    = [null_resource.maven_build]
}
