############################
# Networking
############################
output "vpc_id" {
  value = module.vpc.id
}

############################
# Kubernetes
############################
output "kubernetes_cluster_id" {
  value = module.kubernetes.cluster_id
}

output "kubernetes_endpoint" {
  value = module.kubernetes.endpoint
}

output "kubeconfig" {
  value       = module.kubernetes.kubeconfig_raw
  sensitive   = true
  description = "terraform output -raw kubeconfig > kubeconfig-prod.yaml"
}

output "kubeconfig_command" {
  value = "terraform output -raw kubeconfig > kubeconfig-prod.yaml && export KUBECONFIG=$PWD/kubeconfig-prod.yaml"
}

############################
# PostgreSQL
############################
output "database_host" {
  value = module.postgres.database_host
}

output "database_port" {
  value = module.postgres.database_port
}

output "database_name" {
  value = module.postgres.database_name
}

output "database_user" {
  value = module.postgres.database_user
}

output "database_password" {
  value     = module.postgres.database_password
  sensitive = true
}

output "database_url" {
  value     = "postgresql://${module.postgres.database_user}:PASSWORD@${module.postgres.database_host}:${module.postgres.database_port}/${module.postgres.database_name}?sslmode=require"
  sensitive = false
  description = "JDBC-style URL — substitute password from database_password output"
}

############################
# Redis
############################
output "redis_host" {
  value = module.redis.host
}

output "redis_port" {
  value = module.redis.port
}

output "redis_password" {
  value     = module.redis.password
  sensitive = true
}

############################
# Spaces (S3-compatible)
############################
output "spaces_app_bucket" {
  value = try(module.spaces[0].app_bucket_name, null)
}

output "spaces_logs_bucket" {
  value = try(module.spaces[0].logs_bucket_name, null)
}

output "spaces_endpoint" {
  value       = "https://${var.region}.digitaloceanspaces.com"
  description = "Set as AWS_S3_ENDPOINT / spring.cloud.aws.s3.endpoint"
}

############################
# Container Registry
############################
output "registry_endpoint" {
  value = try(module.registry[0].endpoint, "not created")
}

output "registry_ci_credentials" {
  value     = try(module.registry[0].ci_docker_credentials, null)
  sensitive = true
}

############################
# Messaging (RabbitMQ)
############################
output "rabbitmq_host" {
  value = "rabbitmq.messaging.svc.cluster.local"
}

output "rabbitmq_port" {
  value = 5672
}

output "rabbitmq_username" {
  value = var.rabbitmq_username
}

############################
# DNS / TLS
############################
output "certificate_id" {
  value = try(module.domain[0].certificate_id, "domain not configured")
}

output "domain_fqdn" {
  value = try(module.domain[0].apex_record_fqdn, "domain not configured")
}

############################
# Firewall
############################
output "firewall_id" {
  value = module.firewall.id
}

############################
# Post-apply helpers
############################
output "get_lb_ip_command" {
  value = "kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

output "push_image_example" {
  value = "docker tag app:latest ${try(module.registry[0].endpoint, "REGISTRY")}/app:latest && docker push ${try(module.registry[0].endpoint, "REGISTRY")}/app:latest"
}
