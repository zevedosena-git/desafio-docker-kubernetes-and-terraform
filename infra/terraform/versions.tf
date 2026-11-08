terraform {
  required_version = ">= 1.5.0, < 2.0.0"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "0.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.14.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.36.0"
    }
  }
}
