# Architecture de partage de données inter-domaines sous Microsoft Fabric
## Cloisonnement Banque de Détail × Assurance — Proof of Concept

**Client :** Crédit Agricole — Direction Innovation & Gouvernance des données  
**Date :** Juin 2026  
**Statut :** Proof of Concept déployé sur tenant Microsoft Fabric

---

## 1. Contexte et enjeux

Le groupe Crédit Agricole regroupe des entités métier aux périmètres distincts : la **banque de détail** (LCL / CADIF) et l'**assurance** (Pacifica). Ces deux domaines partagent une base commune de clients, mais leurs données sont sensibles et soumises à des règles de confidentialité strictes :

- Un conseiller bancaire **ne doit pas** avoir accès au détail des contrats d'assurance de clients qui ne sont pas les siens
- Un gestionnaire assurance **ne doit pas** avoir accès aux données financières bancaires (soldes, mouvements)
- Pourtant, une **vue consolidée** du client est nécessaire pour certains cas d'usage métier (rebond commercial, prévention des risques)

La question posée est donc :

> *Comment permettre à des données d'un domaine d'alimenter un modèle analytique d'un autre domaine, sans que les utilisateurs du domaine cible n'aient accès au domaine source ?*

---

## 2. Architecture déployée

### 2.1 Vue d'ensemble

L'architecture repose sur trois composants Microsoft Fabric combinés :

```
Domaine Banque                          Domaine Assurance
══════════════════════════════          ══════════════════════════════════════════
  WS-Banking                              WS-Insurance
  └─ Lakehouse_Banking                    └─ Lakehouse_Insurance
       ├─ dim_customers       ──────►          ├─ sc_dim_customers        (Shortcut)
       ├─ fact_bank_accounts  ──────►          ├─ sc_fact_bank_accounts   (Shortcut)
       └─ bridge_ins_customers──────►          ├─ sc_bridge_ins_customers (Shortcut)
                                               ├─ insurance_contracts     (données Pacifica)
                                               ├─ insurance_claims
                                               ├─ security_table
                                               └─ SEM_Insurance           (Modèle sémantique)
                                                    ├─ Rôle BankingAdvisor
                                                    └─ Rôle InsuranceUser
```

### 2.2 Les trois mécanismes de protection

#### Mécanisme 1 — Isolation des workspaces Fabric

Chaque domaine dispose de son propre workspace Fabric, avec une gestion d'accès indépendante :

| Utilisateur | WS-Banking | WS-Insurance |
|---|---|---|
| Conseillers bancaires (hugo.lambert, isabelle.fontaine) | ✅ Member | ✅ Member |
| Gestionnaire assurance (sophie.marchand) | ❌ Aucun accès | ✅ Member |

Un utilisateur assurance **ne peut pas naviguer, explorer ou requêter** le workspace bancaire. Il n'en connaît pas l'existence dans son interface Fabric.

#### Mécanisme 2 — OneLake Shortcuts (projection sans copie)

Les **Shortcuts** sont des pointeurs vers des données d'un autre workspace. Ils permettent de **rendre visible** une table d'un domaine dans un autre, sans dupliquer la donnée physiquement.

Points clés de sécurité :
- La donnée reste **physiquement stockée dans WS-Banking** (LH-Banking)
- Le shortcut dans LH-Insurance est une **référence technique** — il s'exécute sous l'identité du service Fabric, pas de l'utilisateur final
- Un utilisateur de WS-Insurance qui tente d'accéder directement à l'URL OneLake de WS-Banking obtient une **erreur d'autorisation 403**
- Les shortcuts exposent uniquement les **tables sélectionnées** — pas tout le lakehouse

#### Mécanisme 3 — Row-Level Security (RLS) dans le Modèle Sémantique

Le modèle sémantique `SEM_Insurance` centralise les données des deux domaines et applique un **filtre dynamique par utilisateur** via deux rôles distincts :

**Rôle `BankingAdvisor`** — pour les conseillers LCL/CADIF :

```
sc_dim_customers      → [advisor_email] = USERPRINCIPALNAME()
security_table        → [user_email]    = USERPRINCIPALNAME()
```
→ Le conseiller ne voit que **ses propres clients**, et uniquement leurs contrats assurance  
→ Il ne voit pas les clients ni les soldes des autres conseillers

**Rôle `InsuranceUser`** — pour les gestionnaires Pacifica :

```
sc_dim_customers       → [customer_id] IN VALUES(sc_bridge_ins_customers[customer_id])
sc_fact_bank_accounts  → FALSE()
security_table         → [user_email] = USERPRINCIPALNAME()
```
→ Le gestionnaire ne voit que les clients ayant **explicitement consenti** au partage de données  
→ Il ne voit **aucune donnée bancaire** (les comptes et soldes sont bloqués à la source par `FALSE()`)

---

## 3. La table de consentement : clé de voûte du dispositif

La table `bridge_ins_customers` matérialise le **consentement explicite** du client au partage de ses données entre les deux entités. Elle est gérée par le domaine bancaire et contient :

| Champ | Description |
|---|---|
| `customer_id` | Identifiant client partagé entre les deux domaines |
| `insurance_consent` | Booléen : le client a-t-il consenti au partage ? |
| `sharing_scope` | Granularité du partage (`FULL` ou `BASIC`) |

Seuls les clients avec `insurance_consent = true` sont visibles par les gestionnaires assurance. Cette table est **alimentée par le domaine bancaire** (qui recueille le consentement) et consommée par le domaine assurance via shortcut — sans que Pacifica puisse la modifier.

---

## 4. Matrice de visibilité des données

| Données | Conseiller bancaire | Gestionnaire assurance |
|---|---|---|
| Identité client (nom, région, segment) | ✅ Ses clients uniquement | ✅ Clients consentants uniquement |
| Solde et produits bancaires | ✅ Ses clients | ❌ Bloqué |
| Contrats d'assurance | ✅ Clients consentants de son portefeuille | ✅ Ses clients consentants |
| Sinistres | ✅ Clients consentants de son portefeuille | ✅ Ses clients consentants |
| Données des autres conseillers | ❌ Bloqué | ❌ Bloqué |
| Email / identité des autres utilisateurs | ❌ Bloqué | ❌ Bloqué |

---

## 5. Scénarios de test déployés

### Compte de test — Conseiller bancaire

| Paramètre | Valeur |
|---|---|
| Compte | `hugo.lambert@MngEnvMCAP578215.onmicrosoft.com` |
| Rôle RLS | `BankingAdvisor` |
| Portefeuille | CUS-001 Marie Dupont, CUS-002 Jean Martin, CUS-005 Isabelle Moreau, CUS-007 Claire Laurent, CUS-009 Nathalie Garcia |
| Contrats assurance visibles | CTR-001, CTR-002 (Marie Dupont), CTR-003 (Jean Martin), CTR-005 (Claire Laurent), CTR-006 (Nathalie Garcia) |

### Compte de test — Gestionnaire assurance

| Paramètre | Valeur |
|---|---|
| Compte | `sophie.marchand@MngEnvMCAP578215.onmicrosoft.com` |
| Rôle RLS | `InsuranceUser` |
| Clients visibles | CUS-001, CUS-002, CUS-004, CUS-007, CUS-009 (consentement `true` uniquement) |
| Données bancaires | ❌ Aucune (soldes masqués) |

---

## 6. Garanties de conformité

### Étanchéité des couches

Le cloisonnement repose sur **trois couches indépendantes** : si l'une venait à être contournée, les deux autres restent actives.

```
Tentative d'accès non autorisé
        │
        ▼
┌───────────────────────────────┐
│  Couche 1 : Workspace Fabric  │ ← Accès refusé si pas membre du workspace
│  (contrôle d'accès Entra ID)  │
└───────────────┬───────────────┘
                │ (si membre)
                ▼
┌───────────────────────────────┐
│  Couche 2 : Shortcut OneLake  │ ← Données source inaccessibles directement
│  (identité service, pas user) │
└───────────────┬───────────────┘
                │ (si accès modèle)
                ▼
┌───────────────────────────────┐
│  Couche 3 : RLS Sémantique    │ ← Filtre ligne par ligne selon l'identité
│  (USERPRINCIPALNAME() / DAX)  │
└───────────────────────────────┘
```

### Traçabilité

- Tous les accès au modèle sémantique sont tracés dans les **journaux d'activité Fabric**
- La table `security_table` constitue un registre auditable des habilitations par utilisateur
- Les consentements sont versionnés dans `bridge_ins_customers` côté domaine bancaire

---

## 7. Perspectives et évolutions

| Évolution | Description |
|---|---|
| **Object-Level Security (OLS)** | Masquage de colonnes entières (ex : `balance`) selon le rôle, sans `FALSE()` |
| **Gouvernance via Purview** | Classification des tables sensibles et politiques d'accès centralisées |
| **Automatisation du consentement** | Mise à jour en temps réel de `bridge_ins_customers` depuis le SI bancaire |
| **Multi-entités** | Extension du modèle à d'autres domaines (crédit, patrimoine, leasing) avec le même pattern shortcut + RLS |
| **Audit d'accès** | Rapport Power BI sur les accès par rôle, fréquence, données consultées |

---

## 8. Références techniques

| Composant | Technologie | Documentation |
|---|---|---|
| Stockage | Microsoft Fabric OneLake (Delta Parquet) | [aka.ms/fabric-onelake](https://aka.ms/fabric-onelake) |
| Partage inter-workspace | OneLake Shortcuts | [aka.ms/onelake-shortcuts](https://aka.ms/onelake-shortcuts) |
| Modèle analytique | Direct Lake Semantic Model (TMDL) | [aka.ms/direct-lake](https://aka.ms/direct-lake) |
| Sécurité des données | Row-Level Security DAX | [aka.ms/pbi-rls](https://aka.ms/pbi-rls) |
| Gestion des identités | Microsoft Entra ID (Azure AD) | [aka.ms/entra](https://aka.ms/entra) |
| Déploiement | Fabric REST API + PowerShell | [aka.ms/fabric-api](https://aka.ms/fabric-api) |

---

*Document produit dans le cadre du PoC CA-GIP — Architecture données cross-domaine Microsoft Fabric*
