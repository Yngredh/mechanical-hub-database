# =============================================================================
# MongoDB do mechanical-hub-orchestrator (ADR-0004, infrastructure.md §3)
# =============================================================================
#
# Uma instancia em StatefulSet no EKS, iniciada como replica set de um no:
# transacoes multi-documento (saga + historico + outbox) so existem em replica
# set. Sem tolerancia a perda do pod — aceito no Lab.
#
# DocumentDB nao e liberado no AWS Academy Lab, por isso o banco roda dentro
# do cluster do mechanical-hub-infra.

terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

locals {
  labels = merge(var.labels, {
    "app.kubernetes.io/name"       = "mongodb"
    "app.kubernetes.io/instance"   = var.name
    "app.kubernetes.io/component"  = "database"
    "app.kubernetes.io/part-of"    = "mechanical-hub-orchestrator"
    "app.kubernetes.io/managed-by" = "terraform"
  })

  selector = {
    "app.kubernetes.io/name"     = "mongodb"
    "app.kubernetes.io/instance" = var.name
  }

  secret_name = "${var.name}-credentials"

  # Host DNS estavel do unico pod: <sts>-0.<svc>.<ns>.svc.cluster.local. E o
  # endereco gravado no replica set; sobrevive a recriacao do pod.
  host = "${var.name}-0.${var.name}.${var.namespace}.svc.cluster.local"

  # file() e nao templatefile(): o script usa ${...} de template string do JS.
  init_script = file("${path.module}/init-replica-set.js")
}

# ── Namespace ────────────────────────────────────────────────────────────────

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

# ── Credenciais ──────────────────────────────────────────────────────────────
#
# Geradas aqui e guardadas so no Secret (e no state, que ja e privado). O
# orchestrator monta a URI a partir de mongodb_host/port/replica_set/database
# e le usuario e senha deste Secret.

resource "random_password" "root" {
  length  = 32
  special = false
}

resource "random_password" "app" {
  length  = 32
  special = false
}

# Keyfile do replica set: autenticacao interna entre membros, exigida pelo
# mongod quando --replSet e --auth estao juntos. Apenas caracteres base64.
resource "random_password" "keyfile" {
  length  = 756
  special = false
}

resource "kubernetes_secret_v1" "credentials" {
  metadata {
    name      = local.secret_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  data = {
    "root-username" = var.root_username
    "root-password" = random_password.root.result
    "username"      = var.app_username
    "password"      = random_password.app.result
    "database"      = var.database
    "keyfile"       = random_password.keyfile.result
  }
}

# ── Service headless ─────────────────────────────────────────────────────────

resource "kubernetes_service_v1" "headless" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    cluster_ip = "None"
    selector   = local.selector

    # O mongod precisa resolver o proprio host do replica set ja na subida,
    # antes de ficar pronto; sem isto ele demora a reassumir PRIMARY quando o
    # pod volta depois do fim da sessao do Lab.
    publish_not_ready_addresses = true

    port {
      name        = "mongodb"
      port        = var.port
      target_port = var.port
    }
  }
}

# ── StatefulSet ──────────────────────────────────────────────────────────────

resource "kubernetes_stateful_set_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    service_name = kubernetes_service_v1.headless.metadata[0].name
    replicas     = 1

    selector {
      match_labels = local.selector
    }

    template {
      metadata {
        labels = local.labels
        annotations = {
          # Troca de credenciais ou keyfile reinicia o pod.
          "checksum/credentials" = sha256(jsonencode(kubernetes_secret_v1.credentials.data))
        }
      }

      spec {
        termination_grace_period_seconds = 30

        security_context {
          # UID/GID do usuario mongodb na imagem oficial: o volume de dados
          # precisa ser gravavel por ele.
          fs_group = 999
        }

        # O mongod recusa keyfile legivel por outros usuarios, e volumes de
        # Secret sao montados como root. A copia num emptyDir com dono 999 e
        # modo 0400 resolve sem depender de fsGroup.
        init_container {
          name    = "keyfile"
          image   = var.image
          command = ["sh", "-c", "cp /keyfile-src/keyfile /keyfile/keyfile && chown 999:999 /keyfile/keyfile && chmod 0400 /keyfile/keyfile"]

          volume_mount {
            name       = "keyfile-src"
            mount_path = "/keyfile-src"
            read_only  = true
          }

          volume_mount {
            name       = "keyfile"
            mount_path = "/keyfile"
          }
        }

        container {
          name  = "mongod"
          image = var.image

          args = [
            "--replSet", var.replica_set_name,
            "--keyFile", "/keyfile/keyfile",
            "--bind_ip_all",
            "--port", tostring(var.port),
            "--wiredTigerCacheSizeGB", tostring(var.wiredtiger_cache_size_gb),
          ]

          # A imagem oficial cria o usuario root na primeira subida (volume
          # vazio). O replica set e o usuario do orchestrator ficam com o Job.
          env {
            name = "MONGO_INITDB_ROOT_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.credentials.metadata[0].name
                key  = "root-username"
              }
            }
          }

          env {
            name = "MONGO_INITDB_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.credentials.metadata[0].name
                key  = "root-password"
              }
            }
          }

          port {
            name           = "mongodb"
            container_port = var.port
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          # Pronto = mongod respondendo. Nao exige PRIMARY de proposito: o
          # rs.initiate() roda no Job, que so comeca depois do rollout.
          readiness_probe {
            exec {
              command = ["mongosh", "--quiet", "--port", tostring(var.port), "--eval", "db.adminCommand({ ping: 1 }).ok"]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6
          }

          liveness_probe {
            exec {
              command = ["mongosh", "--quiet", "--port", tostring(var.port), "--eval", "db.adminCommand({ ping: 1 }).ok"]
            }
            initial_delay_seconds = 60
            period_seconds        = 20
            timeout_seconds       = 5
            failure_threshold     = 6
          }

          volume_mount {
            name       = "data"
            mount_path = "/data/db"
          }

          volume_mount {
            name       = "keyfile"
            mount_path = "/keyfile"
            read_only  = true
          }
        }

        volume {
          name = "keyfile-src"
          secret {
            secret_name = kubernetes_secret_v1.credentials.metadata[0].name
            items {
              key  = "keyfile"
              path = "keyfile"
            }
          }
        }

        volume {
          name = "keyfile"
          empty_dir {
            medium = "Memory"
          }
        }

        # Sem persistencia (EBS CSI indisponivel), os dados vivem no no.
        dynamic "volume" {
          for_each = var.persistence_enabled ? [] : [1]
          content {
            name = "data"
            empty_dir {}
          }
        }
      }
    }

    # EBS gp3 com WaitForFirstConsumer: o volume nasce na AZ do no escolhido e
    # o PV fica preso a ela, entao o pod volta para um no da mesma AZ quando os
    # nos religam na sessao seguinte do Lab.
    dynamic "volume_claim_template" {
      for_each = var.persistence_enabled ? [1] : []
      content {
        metadata {
          name   = "data"
          labels = local.labels
        }

        spec {
          access_modes       = ["ReadWriteOnce"]
          storage_class_name = var.storage_class_name

          resources {
            requests = {
              storage = var.storage_size
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !var.persistence_enabled || try(length(var.storage_class_name) > 0, false)
      error_message = "Com persistence_enabled = true e preciso informar storage_class_name (output storage_class_name do mechanical-hub-infra)."
    }
  }
}

# ── Inicializacao do replica set e do usuario do orchestrator ────────────────

resource "kubernetes_config_map_v1" "init" {
  metadata {
    name      = "${var.name}-init"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  data = {
    "init-replica-set.js" = local.init_script
  }
}

# Idempotente: rs.initiate() so quando o replica set ainda nao existe, e
# createUser/updateUser conforme o usuario exista ou nao.
#
# O Kubernetes apaga o Job ttl_seconds_after_finished depois de concluido, e
# o proximo apply o recria e reexecuta. E proposital: no modo emptyDir os
# dados (e com eles o replica set) somem quando o pod muda de no, e um novo
# apply devolve o banco ao estado esperado sem passo manual.
resource "kubernetes_job_v1" "init" {
  metadata {
    name      = "${var.name}-init"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    backoff_limit              = 4
    ttl_seconds_after_finished = 600

    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/component" = "init" })
        annotations = {
          "checksum/script" = sha256(local.init_script)
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name    = "init"
          image   = var.image
          command = ["sh", "-c"]
          args = [<<-EOT
            set -e
            until mongosh --quiet --host "$MONGODB_HOST" --port "$MONGODB_PORT" --eval 'db.adminCommand({ ping: 1 }).ok' >/dev/null 2>&1; do
              echo "Aguardando o mongod em $MONGODB_HOST:$MONGODB_PORT..."
              sleep 5
            done
            mongosh --quiet \
              --host "$MONGODB_HOST" --port "$MONGODB_PORT" \
              --username "$MONGODB_ROOT_USERNAME" --password "$MONGODB_ROOT_PASSWORD" \
              --authenticationDatabase admin \
              /scripts/init-replica-set.js
          EOT
          ]

          env {
            name  = "MONGODB_HOST"
            value = local.host
          }

          env {
            name  = "MONGODB_PORT"
            value = tostring(var.port)
          }

          env {
            name  = "MONGODB_REPLICA_SET"
            value = var.replica_set_name
          }

          env {
            name  = "MONGODB_DATABASE"
            value = var.database
          }

          env {
            name = "MONGODB_ROOT_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.credentials.metadata[0].name
                key  = "root-username"
              }
            }
          }

          env {
            name = "MONGODB_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.credentials.metadata[0].name
                key  = "root-password"
              }
            }
          }

          env {
            name = "MONGODB_APP_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.credentials.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "MONGODB_APP_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.credentials.metadata[0].name
                key  = "password"
              }
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }
        }

        volume {
          name = "scripts"
          config_map {
            name = kubernetes_config_map_v1.init.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "10m"
    update = "10m"
  }

  depends_on = [kubernetes_stateful_set_v1.this]
}
