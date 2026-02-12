terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.7.1"
    }
    # Note: we intentionally avoid using kubernetes_* resources here because they
    # check CRDs during plan. The provider is still declared so the parent module
    # can pass its configuration without Terraform emitting warnings.
    # kubernetes = {
    #   source  = "hashicorp/kubernetes"
    #   version = ">= 2.25.0"
    # }
  }
}
