locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${local.name_prefix}-db-subnet-group" })
}

# ── Security Group ────────────────────────────────────────────────────────────
#
# ADR-0002 ("Acesso ao banco: liberacao por CIDR"): o banco atende a dois
# consumidores — os pods no EKS e as Lambdas de autenticacao. As Lambdas sao
# criadas em `mechanical-hub-auth`, que e aplicado DEPOIS deste repositorio;
# referenciar o security group delas aqui criaria dependencia circular entre
# repositorios. Por isso a liberacao e feita pelo CIDR das subnets privadas,
# onde todos os consumidores residem. O banco nao e exposto publicamente.

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Allow PostgreSQL access from workloads in the private subnets"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-rds-sg" })
}

# Regra por CIDR de subnet privada (EKS nodes e Lambdas em VPC).
resource "aws_security_group_rule" "postgres_from_private_subnets" {
  for_each = toset(var.private_subnet_cidrs)

  type              = "ingress"
  security_group_id = aws_security_group.rds.id
  from_port         = var.db_port
  to_port           = var.db_port
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  description       = "PostgreSQL from private subnet ${each.value}"
}

# Security groups adicionais autorizados (opcional). Deixe vazio para operar
# apenas com a liberacao por CIDR descrita na ADR-0002.
resource "aws_security_group_rule" "postgres_from_security_groups" {
  for_each = toset(var.allowed_security_group_ids)

  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = each.value
  description              = "PostgreSQL from security group ${each.value}"
}

# ── RDS Instance ──────────────────────────────────────────────────────────────

resource "aws_db_instance" "this" {
  identifier        = "${local.name_prefix}-postgres"
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.db_instance_class
  allocated_storage = var.allocated_storage
  storage_encrypted = var.storage_encrypted

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = var.db_port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period

  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot

  apply_immediately = var.apply_immediately

  tags = merge(var.tags, { Name = "${local.name_prefix}-postgres" })
}
