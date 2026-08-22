output "vpc_id" {
  description = "VPC de teste."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR da VPC de teste."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Subnets privadas criadas pela fixture."
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas criadas pela fixture."
  value       = aws_subnet.private[*].cidr_block
}
