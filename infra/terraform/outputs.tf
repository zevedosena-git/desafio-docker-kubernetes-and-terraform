output "mural_url" {
  description = "Acesso HTTP ao Mural."
  value       = "http://${var.host}${var.http_port == 80 ? "" : ":${var.http_port}"}"
}

output "kubeconfig_path" {
  description = "Arquivo exclusivo para kubectl --kubeconfig; removido no destroy."
  value       = local.kubeconfig_path
}

output "cluster_name" {
  value = kind_cluster.mural.name
}
