
resource "kubernetes_namespace_v1" "eks" {
  metadata {

    labels = {
      app = var.service-name
    }
    name = var.service-name
  }

}

resource "kubernetes_storage_class_v1" "eks" {
  metadata {
    name = "ebs"
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
}

data "aws_instances" "node-group-instances" {
  instance_tags = {
    "eks:nodegroup-name" = var.eks-node-group-name
  }
  instance_state_names = ["running"]
}

data "aws_instance" "node-group-instance" {
  for_each = toset(data.aws_instances.node-group-instances.ids)
  instance_id = each.value
}

resource "kubernetes_persistent_volume_v1" "eks" {
  metadata {
    name = var.service-name
    labels = {
      app  = var.service-name
      type = "local"
    }
  }
  spec {
    storage_class_name = kubernetes_storage_class_v1.eks.metadata.0.name
    claim_ref {
      name      = var.service-name
      namespace = kubernetes_namespace_v1.eks.metadata.0.name
    }
    capacity = {
      storage = "5Gi"
    }
    access_modes = ["ReadWriteOnce"]
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key = "kubernetes.io/hostname"
            operator = "In"
            values = [for k, v in data.aws_instance.node-group-instance : v.private_dns]
          }
        }
      }
    }

    persistent_volume_source {
      local {
        path = "/mnt"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "eks" {
  metadata {
    name      = var.service-name
    namespace = kubernetes_namespace_v1.eks.metadata.0.name
  }
  spec {
    storage_class_name = kubernetes_storage_class_v1.eks.metadata.0.name
    access_modes       = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "3Gi"
      }
    }
    volume_name = kubernetes_persistent_volume_v1.eks.metadata.0.name
  }
}

resource "kubernetes_deployment_v1" "eks" {
  metadata {
    name = var.service-name
    labels = {
      app = var.service-name
    }
    namespace = kubernetes_namespace_v1.eks.metadata.0.name
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = var.service-name
      }
    }

    template {
      metadata {
        labels = {
          app = var.service-name
        }
      }

      spec {
        security_context {
          fs_group    = 1000
          run_as_user = 1000
        }
        image_pull_secrets {
          name = kubernetes_secret_v1.packbroker-image.metadata.0.name
        }
        container {
          image = "244586165116.dkr.ecr.ca-central-1.amazonaws.com/pack_broker:1.0.0"
          name  = var.service-name

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "0.2"
              memory = "64Mi"
            }
          }
          port {
            container_port = 9292
            name           = "httpport"
          }
          env {
            name = "POSTGRES_PASSWORD"
            value = "adminpass"
          }
          env {
            name = "POSTGRES_USER"
            value = "eks-node"
          }
          env {
            name = "POSTGRES_DB"
            value = "packbroker"
          }
          # security_context {
          #   privileged = false
          #   allow_privilege_escalation = false
          #   read_only_root_filesystem = true
          # }
          # liveness_probe {
          #   http_get {
          #     path = "/login"
          #     port = 9292
          #   }
          #   initial_delay_seconds = 60
          #   period_seconds        = 10
          #   timeout_seconds       = 5
          #   failure_threshold     = 3
          # }

        }
        service_account_name = kubernetes_service_account_v1.eks.metadata.0.name
       
      }
    }
  }
}

resource "kubernetes_service_v1" "eks" {
  metadata {
    name      = var.service-name
    namespace = kubernetes_namespace_v1.eks.metadata.0.name
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/path"   = "/"
      "prometheus.io/port"   = "80"
    }
  }
  spec {
    selector = {
      app = var.service-name
    }
    port {
      port        = 80
      target_port = 9292
      protocol = "TCP"
    }
    type = "NodePort"
    
  }
}

resource "kubernetes_ingress_v1" "eks" {
  metadata {
    namespace = kubernetes_namespace_v1.eks.metadata.0.name
    name = var.service-name
    annotations = {
      "kubernetes.io/ingress.class": "alb"
      "alb.ingress.kubernetes.io/scheme": "internet-facing"
    }
  }
  spec {
    default_backend {
      service {
        name = kubernetes_service_v1.eks.metadata.0.name
        port {
          number = 80
        }
      }
    }
    # ingress_class_name = "alb"
    rule {
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.eks.metadata.0.name
              port {
                number = 80
              }
            }
          }
          path = "/"
          # path_type = "Prefix"
        }
      }
    }

    # tls {
    #   secret_name = "tls-secret"
    # }
  }
}

# resource "kubernetes_namespace_v1" "test" {
#   metadata {
#     name = "game"
#   }
# }

# resource "kubernetes_deployment_v1" "name" {
#   metadata {
#     name = "game"
#     namespace = kubernetes_namespace_v1.eks.metadata.0.name
#   }
#   spec {
#     selector {
#       match_labels = {
#         "app.kubernetes.io/name" = "app-2048"
#       }
#     }
#     replicas = 2
#     template {
#       metadata {
#         labels = {
#           "app.kubernetes.io/name" = "app-2048"
#         }
#       }
#       spec {
#         container {
#           image = "public.ecr.aws/l6m2t8p7/docker-2048:latest"
#           image_pull_policy = "Always"
#           name = "app-2048"
#           port {
#             container_port = 80
#           }
#         }
#       }
#     }
#   }
# }

# resource "kubernetes_service_v1" "name" {
#   metadata {
#     name = "game"
#     namespace = kubernetes_namespace_v1.eks.metadata.0.name
#   }
#   spec {
#     port {
#       port = 80
#       target_port = 80
#       protocol = "TCP"
#     }
#     type = "NodePort"
#     selector = {
#       "app.kubernetes.io/name": "app-2048"
#     }
#   }
# }

# resource "kubernetes_ingress_v1" "name" {
#   metadata {
#     name = "game"
#     namespace = kubernetes_namespace_v1.eks.metadata.0.name
#     annotations = {
#       "alb.ingress.kubernetes.io/scheme" = "internet-facing"
#       # "alb.ingress.kubernetes.io/target-type" = "ip"
#       "kubernetes.io/ingress.class": "alb"
#     }
#   }
#   spec {
#   #  ingress_class_name = "alb"
#    rule {
#      http {
#         path {
#           path = "/"
#           # path_type = "Prefix"
#           backend {
#             service {
#               name = kubernetes_service_v1.name.metadata.0.name
#               port {
#                 number = 80
#               }
#             }
#           }
#         }
#      }
#    } 
#   }
# }

     