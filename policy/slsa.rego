package main

import rego.v1

# --- Politique de l'organisation (groupe G2) ---
expected_builder := "https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml"
expected_source  := "github.com/BouazzaZayd/app-devsecops-slsa"
expected_entry   := ".github/workflows/release.yml"

builder_id := input.predicate.builder.id
source_uri := input.predicate.invocation.configSource.uri
entrypoint := input.predicate.invocation.configSource.entryPoint
commit     := input.predicate.invocation.configSource.digest.sha1
event      := input.predicate.invocation.environment.github_event_name

# 1. Builder officiel SLSA L3
deny contains msg if {
  not startswith(builder_id, expected_builder)
  msg := sprintf("builder non officiel: %q", [builder_id])
}

# 2. Depot source exact
deny contains msg if {
  not contains(source_uri, expected_source)
  msg := sprintf("source non autorisee: %q", [source_uri])
}

# 3. Workflow exact
deny contains msg if {
  entrypoint != expected_entry
  msg := sprintf("workflow non autorise: %q", [entrypoint])
}

# 4. Branche main ou tag v*
ref_ok if endswith(source_uri, "@refs/heads/main")
ref_ok if contains(source_uri, "@refs/tags/v")
deny contains msg if {
  not ref_ok
  msg := sprintf("ref non autorisee: %q", [source_uri])
}

# 5. Commit present
deny contains msg if {
  not commit
  msg := "commit source absent"
}
deny contains msg if {
  commit == ""
  msg := "commit source vide"
}

# 6. Declencheur autorise
allowed_event if event == "push"
allowed_event if event == "release"
allowed_event if event == "workflow_dispatch"
deny contains msg if {
  not allowed_event
  msg := sprintf("declencheur non autorise: %q", [event])
}
