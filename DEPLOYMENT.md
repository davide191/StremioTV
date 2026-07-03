# Déploiement TestFlight (tests internes)

Deux apps sont livrées sur TestFlight, **en tests internes uniquement** (pas de
Beta App Review, build dispo dès la fin du traitement Apple) :

| App | Cible | Bundle ID | Appareils |
|-----|-------|-----------|-----------|
| StremioTV | `StremioTV-iOS` | `com.nicolasbataille.stremiotv` | iPhone + iPad |
| StremioTV Apple TV | `StremioTV` | `com.nicolasbataille.stremiotv.tv` | Apple TV |

Le build + l'upload se déclenchent **au push d'un tag `v*`** via GitHub Actions
(`.github/workflows/testflight.yml`). Signature **automatique** (certificats
« cloud-managed » gérés par Xcode via la clé API — aucun dépôt de certificats à
maintenir).

---

## 1. Réglages App Store Connect (une seule fois)

### a. Clé App Store Connect API
App Store Connect → **Users and Access → Integrations → App Store Connect API**
→ **Generate API Key** — rôle **Admin** (⚠️ requis).
- Télécharge le fichier `AuthKey_XXXXXXXXXX.p8` (**téléchargeable une seule fois**).
- Note le **Key ID** et l'**Issuer ID** (en haut de la page).

> **Pourquoi Admin ?** La signature de distribution « cloud-managed » (certificat
> App Store créé automatiquement par Xcode via la clé) n'est autorisée qu'aux
> clés **Admin** / **Account Holder**. Une clé **App Manager** peut enregistrer
> les Bundle IDs et téléverser des builds, mais échoue à l'export avec
> « Cloud signing permission error ».

### b. Team ID
[developer.apple.com/account](https://developer.apple.com/account) → **Membership**
→ **Team ID** (10 caractères).

### c. Bundle IDs (via clé API — idempotent)
```bash
bundle install
ASC_KEY_ID=... ASC_ISSUER_ID=... P8_PATH=~/Downloads/AuthKey_XXXX.p8 \
  bundle exec ruby scripts/register_bundle_ids.rb
```
> S'enregistrent aussi automatiquement au 1er build (`-allowProvisioningUpdates`).

### d. Fiches d'app (⚠️ UI web — pas la clé API)
Créer une *fiche d'app* n'est **pas** possible via clé API (limitation Apple).
Comme iOS et tvOS ont des Bundle IDs différents, ce sont **deux fiches** :

App Store Connect → **Apps → ➕ New App**, deux fois :

| # | Plateforme | Bundle ID | Nom |
|---|-----------|-----------|-----|
| 1 | **iOS** | `com.nicolasbataille.stremiotv` | StremioTV |
| 2 | **tvOS** | `com.nicolasbataille.stremiotv.tv` | StremioTV Apple TV |

(SKU = un texte unique quelconque, ex. le Bundle ID.)

> Alternative CLI (Apple ID + 2FA interactive, pas la clé API) :
> `APPLE_ID=toi@mail APPLE_TEAM_ID=... bundle exec fastlane register_apps`

### d. Testeurs internes
Pour **chaque** app : TestFlight → **Internal Testing** → crée un groupe
interne → ajoute les testeurs (doivent être des utilisateurs de ton équipe App
Store Connect). Les testeurs internes reçoivent **chaque build** automatiquement.

---

## 2. Secrets GitHub

Repo → **Settings → Secrets and variables → Actions → New repository secret** :

| Secret | Valeur |
|--------|--------|
| `ASC_KEY_ID` | Key ID de la clé API |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXXXXXXXX.p8` (copie la sortie) |
| `APPLE_TEAM_ID` | ton Team ID |

```bash
# macOS : encoder la clé .p8 en base64 et la copier dans le presse-papier
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

---

## 3. Déclencher un déploiement

```bash
git tag v0.2.0
git push origin v0.2.0
```

GitHub Actions compile les deux apps et les envoie sur TestFlight. La **version
marketing** provient du tag (`v0.2.0` → `0.2.0`), le **numéro de build** du
numéro de run CI (toujours croissant).

Déclenchement **manuel** possible : onglet **Actions → TestFlight → Run workflow**.

### En local (facultatif)

```bash
export ASC_KEY_ID=...            ASC_ISSUER_ID=...
export ASC_KEY_P8_BASE64="$(base64 -i AuthKey_XXXXXXXXXX.p8)"
export APPLE_TEAM_ID=...
bundle exec fastlane beta        # iOS + tvOS
# ou : fastlane beta_ios   /   fastlane beta_tvos
```

---

## Notes

- **Tests internes seulement** : aucune revue Apple, jusqu'à 100 testeurs
  internes, build actif ~90 jours.
- Chaque tag doit avoir une version **différente** de la précédente au besoin ;
  le numéro de build est unique par run CI, donc deux tags à la même version
  marketing restent acceptés par TestFlight.
- Runner CI : `macos-15` (Xcode latest-stable). Le premier run télécharge VLCKit
  (~1 Go, mis en cache ensuite).
