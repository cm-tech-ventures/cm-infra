terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30, < 7"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
