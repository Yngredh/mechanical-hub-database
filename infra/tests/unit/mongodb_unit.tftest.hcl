# Modulo mongodb: StatefulSet do MongoDB do orchestrator (ADR-0004).
#
# Cobre o que so apareceria no apply, contra o cluster real: o replica set
# (sem --replSet nao ha transacao multi-documento), a replica unica, os
# requests/limits e a troca de PVC por emptyDir quando a persistencia esta
# desligada.
#
# Rodar a partir de infra/:
#   terraform test -test-directory=tests/unit -filter=tests/unit/mongodb_unit.tftest.hcl

mock_provider "kubernetes" {}
mock_provider "random" {}

variables {
  namespace          = "mongodb"
  storage_class_name = "gp3"
}

run "statefulset_runs_a_single_node_replica_set" {
  command = plan

  module {
    source = "./modules/mongodb"
  }

  assert {
    condition     = tonumber(kubernetes_stateful_set_v1.this.spec[0].replicas) == 1
    error_message = "O MongoDB roda com exatamente 1 replica (replica set de um no)."
  }

  assert {
    condition = (
      contains(kubernetes_stateful_set_v1.this.spec[0].template[0].spec[0].container[0].args, "--replSet") &&
      contains(kubernetes_stateful_set_v1.this.spec[0].template[0].spec[0].container[0].args, "rs0")
    )
    error_message = "O mongod precisa subir com --replSet rs0: transacoes multi-documento exigem replica set."
  }

  assert {
    condition     = contains(kubernetes_stateful_set_v1.this.spec[0].template[0].spec[0].container[0].args, "--keyFile")
    error_message = "Com autenticacao e replica set o mongod exige --keyFile."
  }

  assert {
    condition     = output.host == "mongodb-0.mongodb.mongodb.svc.cluster.local"
    error_message = "O host deveria ser o DNS estavel do pod: <sts>-0.<svc>.<ns>.svc.cluster.local."
  }
}

run "statefulset_has_requests_limits_and_readiness" {
  command = plan

  module {
    source = "./modules/mongodb"
  }

  assert {
    condition = (
      kubernetes_stateful_set_v1.this.spec[0].template[0].spec[0].container[0].resources[0].requests["cpu"] == "250m" &&
      kubernetes_stateful_set_v1.this.spec[0].template[0].spec[0].container[0].resources[0].requests["memory"] == "768Mi"
    )
    error_message = "Requests do MongoDB deveriam ser ~0,25 vCPU / 0,75 GiB (infrastructure.md §3)."
  }

  assert {
    condition = (
      length(kubernetes_stateful_set_v1.this.spec[0].template[0].spec[0].container[0].resources[0].limits["cpu"]) > 0 &&
      length(kubernetes_stateful_set_v1.this.spec[0].template[0].spec[0].container[0].resources[0].limits["memory"]) > 0
    )
    error_message = "O MongoDB precisa de limits de CPU e memoria."
  }

  assert {
    condition     = length(kubernetes_stateful_set_v1.this.spec[0].template[0].spec[0].container[0].readiness_probe) == 1
    error_message = "O MongoDB precisa de readiness probe."
  }
}

run "persistence_uses_a_pvc_on_the_storage_class" {
  command = plan

  module {
    source = "./modules/mongodb"
  }

  assert {
    condition     = length(kubernetes_stateful_set_v1.this.spec[0].volume_claim_template) == 1
    error_message = "Com persistencia ligada deveria haver um volume_claim_template."
  }

  assert {
    condition     = kubernetes_stateful_set_v1.this.spec[0].volume_claim_template[0].spec[0].storage_class_name == "gp3"
    error_message = "O PVC deveria usar a StorageClass informada (gp3 do mechanical-hub-infra)."
  }

  assert {
    condition = length([
      for v in kubernetes_stateful_set_v1.this.spec[0].template[0].spec[0].volume : v
      if v.name == "data"
    ]) == 0
    error_message = "Com persistencia ligada o volume data vem do PVC, nao de um volume do pod."
  }
}

run "emptydir_when_persistence_is_disabled" {
  command = plan

  module {
    source = "./modules/mongodb"
  }

  variables {
    persistence_enabled = false
    storage_class_name  = null
  }

  assert {
    condition     = length(kubernetes_stateful_set_v1.this.spec[0].volume_claim_template) == 0
    error_message = "Sem persistencia nao deveria haver volume_claim_template."
  }

  assert {
    condition = length([
      for v in kubernetes_stateful_set_v1.this.spec[0].template[0].spec[0].volume : v
      if v.name == "data" && length(v.empty_dir) == 1
    ]) == 1
    error_message = "Sem persistencia o volume data deveria ser um emptyDir."
  }
}

run "persistence_requires_a_storage_class" {
  command = plan

  module {
    source = "./modules/mongodb"
  }

  variables {
    storage_class_name = null
  }

  expect_failures = [kubernetes_stateful_set_v1.this]
}
