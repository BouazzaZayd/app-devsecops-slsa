# Rejouer la démonstration — Keyless Sigstore & provenance SLSA

Ce runbook permet de **reproduire** les quatre scénarios de la démonstration.
Dépôt de référence : `BouazzaZayd/app-devsecops-slsa`.

Identité attendue (inscrite dans le certificat Fulcio) :
```
https://github.com/BouazzaZayd/app-devsecops-slsa/.github/workflows/release.yml@refs/heads/main
émetteur : https://token.actions.githubusercontent.com
```

Résultat attendu des quatre scénarios :

| # | Image | Résultat | Contrôle qui décide |
|---|---|---|---|
| 1 | légitime (notre workflow) | **ADMISE** | les 3 contrôles passent |
| 2 | fork, même workflow, autre compte | **REFUSÉE** | cosign (identité) |
| 3 | poussée à la main, non signée | **REFUSÉE** | cosign (absence de signature) |
| 4 | appelée par tag (mutable) | **REFUSÉE** | vérification par digest |

---

## Prérequis

- Machine de vérification (ex. VM4) avec `cosign` (v3.1.1), `slsa-verifier`,
  `conftest`, `crane`, `docker`, `jq` — installables via `scripts/install-verify-tools.sh`.
- Accès réseau sortant vers `ghcr.io`, `fulcio.sigstore.dev`, `rekor.sigstore.dev`.
- Horloge synchronisée (`sudo timedatectl set-ntp true`) : le certificat Fulcio ne
  vit que 10 minutes, la vérification dépend de l'heure.
- L'image a été construite, signée et tracée par le workflow GitHub `release.yml`
  (pipeline : SAST → SCA → secrets → build → SBOM → signature keyless → provenance SLSA L3).
- La politique `policy/slsa.rego` et le script `scripts/verify-deploy.sh` présents.

---

## Préparation

```bash
# Mot de passe du registre Zot, fourni par l'environnement (jamais en dur)
export ZOT_PASSWORD='<votre-mot-de-passe-zot>'

# Digest immuable de l'image legitime (resolu depuis le tag latest)
DIGEST=$(crane digest ghcr.io/bouazzazayd/app-devsecops-slsa:latest)
echo "DIGEST=$DIGEST"
```

---

## Scénario 1 — Image légitime → ADMISE

Lance le gate complet (les 3 contrôles, puis copie dans Zot et déploiement par digest) :
```bash
./scripts/verify-deploy.sh
```
**Résultat attendu** :
```
== [1/3] cosign verify ... OK signature keyless
== [2/3] slsa-verifier ... OK provenance SLSA L3
== [3/3] conftest ... OK politique Rego
== Copie GHCR -> Zot ... OK digest identique
== Deploiement ... IMAGE ADMISE, DEPLOYEE ET VERIFIEE
```

---

## Scénario 2 — Fork / autre compte → REFUSÉE

Un fork lance le même workflow et obtient une signature valide, mais à une autre
identité. On exige notre identité ; la sienne est refusée :
```bash
REPO=attaquant/fork-malveillant ./scripts/verify-deploy.sh
```
**Résultat attendu** : arrêt dès le premier contrôle —
`[1/3] REFUSE : signature keyless invalide ou mauvaise identité`.

---

## Scénario 3 — Image non signée, poussée à la main → REFUSÉE

Une image poussée directement dans le registre, sans passer par la chaîne, n'a aucune
signature keyless :
```bash
cosign verify \
  --certificate-identity-regexp "(?i)^https://github\.com/BouazzaZayd/app-devsecops-slsa/.*$" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --allow-http-registry 10.0.0.13:5000/app-devsecops:evil
```
**Résultat attendu** : `Error: no matching signatures`.

---

## Scénario 4 — Appelée par tag (mutable) → REFUSÉE

Un tag est une étiquette mutable : il peut être repointé vers une autre image. La
vérification par digest détecte l'échange.
```bash
# Le tag "prod" pointe d'abord vers l'image legitime
crane copy --insecure "ghcr.io/bouazzazayd/app-devsecops-slsa@${DIGEST}" \
  10.0.0.13:5000/app-devsecops-slsa:prod

# Un attaquant repointe le tag "prod" vers une image piegee
crane copy --insecure 10.0.0.13:5000/app-devsecops:evil \
  10.0.0.13:5000/app-devsecops-slsa:prod

# Verifier ce que le tag designe maintenant : l'image piegee, non signee -> refusee
cosign verify \
  --certificate-identity-regexp "(?i)^https://github\.com/BouazzaZayd/app-devsecops-slsa/.*$" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --allow-http-registry 10.0.0.13:5000/app-devsecops-slsa:prod
```
**Résultat attendu** : `Error: no matching signatures`.
Conclusion : déployer par digest (et non par tag) empêche cet échange.

---

## Vérifications complémentaires (facultatives)

**Provenance SLSA L3** (builder officiel + commit) :
```bash
slsa-verifier verify-image "ghcr.io/bouazzazayd/app-devsecops-slsa@${DIGEST}" \
  --source-uri github.com/BouazzaZayd/app-devsecops-slsa \
  --builder-id https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml
```
**Résultat attendu** : `PASSED: SLSA verification passed`.

**Transparence Rekor** : l'entrée publique est consultable sur `https://search.sigstore.dev`.

**DAST** (analyse dynamique de l'appli déployée, depuis une machine du lab) :
```bash
# Nuclei
docker run --rm --network host <image-nuclei> \
  sh -c "nuclei -u http://10.0.0.14:8080 -t /nuclei-templates/ -severity critical,high -nc"
# ZAP (scan API)
docker run --rm -v ~/zap-results:/zap/wrk:rw <image-zap> \
  zap-api-scan.py -t http://10.0.0.14:8080/openapi.json -f openapi -r zap-report.html -l WARN
```

---

## Note de sécurité

Aucun secret n'est stocké dans ce dépôt. Le mot de passe du registre et les clés sont
fournis par l'environnement ou le coffre de la CI, jamais écrits en dur dans le code.
