variable "postgres_password" {
  description = "Senha externa; reutilize a mesma entrada nos dois applies e no destroy."
  type        = string
  sensitive   = true
  nullable    = false
  validation {
    condition     = length(var.postgres_password) > 0
    error_message = "Forneça postgres_password externamente, sem senha padrão."
  }
}

variable "cluster_name" {
  description = "Nome exclusivo para o cluster e tags gerenciadas."
  type        = string
  default     = "mural-mba"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,29}$", var.cluster_name))
    error_message = "Use até 30 letras minúsculas, números ou hífens, iniciando por letra."
  }
}

variable "host" {
  description = "Host HTTP local; deve resolver para 127.0.0.1."
  type        = string
  default     = "mural.localtest.me"
}

variable "http_port" {
  description = "Porta HTTP publicada no host pelo kind."
  type        = number
  default     = 80
  validation {
    condition     = var.http_port >= 1 && var.http_port <= 65535 && floor(var.http_port) == var.http_port
    error_message = "http_port deve ser uma porta TCP válida."
  }
}

variable "https_port" {
  description = "Mapeamento de 443 da topologia; TLS não é configurado neste desafio."
  type        = number
  default     = 443
  validation {
    condition     = var.https_port >= 1 && var.https_port <= 65535 && floor(var.https_port) == var.https_port
    error_message = "https_port deve ser uma porta TCP válida."
  }
}
