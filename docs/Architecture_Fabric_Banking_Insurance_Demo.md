# 🏦 Architecture Microsoft Fabric — Démo Retail Banking × Assurance (Pacifica)

> **Auteur** : Julien — Architecte Data Microsoft Fabric  
> **Date** : Juin 2026  
> **Scénario client** : Crédit Agricole Île-de-France (LCL) × Pacifica (Assurance)  
> **Objectif** : Démontrer l'isolation des données inter-domaines avec OneLake Shortcuts + RLS

---

## 📋 Sommaire

1. [Faisabilité et risques](#1-faisabilité-et-risques)
2. [Architecture sécurisée proposée](#2-architecture-sécurisée-proposée)
3. [Design de la démo — Étapes](#3-design-de-la-démo--étapes)
4. [Modèle de données sample](#4-modèle-de-données-sample)
5. [Flux d'accès utilisateur Assurance](#5-flux-daccès-utilisateur-assurance)
6. [Extension — Assurance Vie / Gestion de Patrimoine](#6-extension--assurance-vie--gestion-de-patrimoine)
7. [Récapitulatif des bonnes pratiques sécurité](#7-récapitulatif-des-bonnes-pratiques-sécurité)
8. [Story client (Storytelling démo)](#8-story-client-storytelling-démo)

---

## 1. Faisabilité et risques

### ✅ C'est techniquement faisable — avec des nuances importantes

Microsoft Fabric permet ce scénario grâce à la combinaison :

| Mécanisme | Rôle |
|---|---|
| **OneLake Shortcuts** | Accès inter-Lakehouse sans copie de données |
| **Row-Level Security (RLS)** | Filtrage des lignes au niveau du Semantic Model |
| **Object-Level Security (OLS)** | Masquage de colonnes ou tables entières |
| **Workspace isolation** | Cloisonnement organisationnel fort |
| **Lakehouse SQL Endpoint** | Surface d'accès SQL avec permissions granulaires |

### ⚠️ Limitations et risques critiques à connaître

#### 🔴 Risque #1 — Les shortcuts ne sont pas des filtres de sécurité

> **Un OneLake Shortcut est un lien de navigation, pas un contrôle d'accès.**

Si le Lakehouse Assurance crée un shortcut vers la table `Customers` du Lakehouse Banking :
- Tout utilisateur ayant accès au **Lakehouse Assurance** verra **toutes les lignes** de `Customers`
- Il n'y a **pas de filtrage natif au niveau du shortcut**

➡️ **La sécurité DOIT être appliquée au niveau du Semantic Model (RLS), pas au niveau du Lakehouse.**

#### 🟡 Risque #2 — Le SQL Endpoint expose les données brutes

Le SQL Analytics Endpoint d'un Lakehouse donne accès direct aux Delta tables via T-SQL.  
Sans RLS au niveau du Semantic Model, un utilisateur peut contourner les rapports Power BI  
et interroger directement les données via SSMS ou un notebook.

➡️ **Mitigation** : Restreindre les permissions SQL Endpoint aux seuls rôles autorisés.  
➡️ Ne jamais donner le rôle `ReadData` sur le SQL Endpoint du Lakehouse Banking aux utilisateurs Assurance.

#### 🟡 Risque #3 — Direct Lake et RLS

En mode **Direct Lake**, le moteur charge les données depuis OneLake directement.  
Le RLS défini dans le Semantic Model **s'applique bien** en Direct Lake — mais uniquement  
si les utilisateurs accèdent via le Semantic Model.  
Un accès direct au Delta Parquet (via notebook ou API) **contourne le RLS**.

#### 🟢 Ce qui est sécurisé par design

- Un utilisateur sans accès workspace Banking ne peut pas naviguer dans ce Lakehouse
- Les permissions Fabric sont héritées par OneLake (pas d'accès si pas de permission workspace ou item)
- Le RLS dans un Semantic Model Fabric s'applique uniformément à tous les consommateurs du modèle

### 🗺️ Où appliquer la sécurité (matrice)

```
Couche               | Mécanisme         | Couvre quoi
---------------------|-------------------|------------------------------------------
Workspace            | Rôles Fabric      | Isolation organisationnelle (qui voit quoi)
Lakehouse (item)     | Item permissions  | Qui peut lire le Lakehouse Insurance
SQL Endpoint         | Grant/Deny SQL    | Qui peut faire des requêtes T-SQL directes
Semantic Model       | RLS / OLS         | Filtrage métier (lignes, colonnes, tables)
OneLake Shortcut     | aucun natif ❌    | Pont de lecture — sécurité héritée du source
```

---

## 2. Architecture sécurisée proposée

### 🏗️ Diagramme d'architecture (textuel)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Microsoft Fabric Tenant — MngEnvMCAP578215.onmicrosoft.com                 │
│                                                                              │
│  ┌─────────────────────────────────┐    ┌──────────────────────────────┐   │
│  │  WS-Banking (LCL / CADIF)        │    │  WS-Insurance (Pacifica)      │   │
│  │  Capacité F64                    │    │  Capacité F64                 │   │
│  │                                  │    │                               │   │
│  │  ┌──────────────────────────┐    │    │  ┌─────────────────────────┐ │   │
│  │  │  LH-Banking              │    │    │  │  LH-Insurance           │ │   │
│  │  │  (Lakehouse source)      │    │    │  │  (Lakehouse cible)      │ │   │
│  │  │                          │    │    │  │                         │ │   │
│  │  │  Tables Delta :          │    │    │  │  Tables NATIVES :       │ │   │
│  │  │  • dim_customers         │◄───┼────┼──│  • insurance_contracts  │ │   │
│  │  │  • fact_accounts         │    │    │  │  • insurance_claims     │ │   │
│  │  │  • fact_transactions     │    │    │  │  • insurance_products   │ │   │
│  │  │  • dim_products          │    │    │  │                         │ │   │
│  │  │  • bridge_ins_customers  │    │    │  │  Shortcuts OneLake :    │ │   │
│  │  │    (table de mapping)    │────┼────┼─►│  • sc_dim_customers ─► │ │   │
│  │  │                          │    │    │  │    LH-Banking/dim_cust  │ │   │
│  │  └──────────────────────────┘    │    │  │  • sc_bridge_ins ─────► │ │   │
│  │                                  │    │  │    LH-Banking/bridge    │ │   │
│  │  ┌──────────────────────────┐    │    │  └─────────────────────────┘ │   │
│  │  │  SM-Banking              │    │    │                               │   │
│  │  │  (Semantic Model interne)│    │    │  ┌─────────────────────────┐ │   │
│  │  │  RLS : rôles internes    │    │    │  │  SM-Insurance           │ │   │
│  │  └──────────────────────────┘    │    │  │  (Semantic Model)       │ │   │
│  │                                  │    │  │                         │ │   │
│  │  Accès : Banking team only       │    │  │  ✅ RLS appliqué ici :  │ │   │
│  │                                  │    │  │  FILTER sur customer_id │ │   │
│  └─────────────────────────────────┘    │  │  = contrats assurance   │ │   │
│                                          │  └─────────────────────────┘ │   │
│                                          │                               │   │
│                                          │  Accès : Insurance team only  │   │
│                                          └──────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  Entra ID Security Groups                                             │   │
│  │  GRP-Banking-Analysts → WS-Banking (Member/Contributor)              │   │
│  │  GRP-Insurance-Analysts → WS-Insurance (Member/Contributor)          │   │
│  │  SP-Fabric-Shortcut → WS-Banking (ReadAll sur LH-Banking uniquement) │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 🔑 Principes clés de l'architecture

#### Principe 1 — Séparation des workspaces par domaine

- **WS-Banking** : isolé, accessible uniquement aux équipes LCL/CADIF
- **WS-Insurance** : isolé, accessible uniquement aux équipes Pacifica
- Aucun utilisateur Assurance n'a accès au workspace Banking

#### Principe 2 — Shortcuts ciblés (surface minimale)

Le Lakehouse Assurance crée des shortcuts **uniquement** vers :
1. `dim_customers` — table clients du Banking (toutes les colonnes, mais RLS filtre les lignes)
2. `bridge_ins_customers` — table de mapping clients-contrats (gérée par Banking, en lecture seule)

Il ne crée **pas** de shortcuts vers :
- `fact_accounts` — comptes bancaires (aucun intérêt pour l'assurance)
- `fact_transactions` — transactions (données confidentielles non pertinentes)
- `dim_products` — produits bancaires (hors périmètre assurance)

#### Principe 3 — RLS au niveau du Semantic Model Insurance

Le Semantic Model `SM-Insurance` définit un rôle `Insurance_User` avec la règle :

```dax
-- Table : sc_dim_customers (shortcut vers dim_customers du Banking)
-- Filtre : ne voir que les clients ayant un contrat assurance actif

[customer_id] IN
    CALCULATETABLE(
        VALUES(insurance_contracts[customer_id]),
        insurance_contracts[contract_status] = "ACTIVE"
    )
```

➡️ Un analyste Pacifica connecté au rapport Power BI :
- **Voit** : les 12 000 clients Pacifica avec leurs données demo
- **Ne voit pas** : les 380 000 autres clients LCL sans contrat assurance

#### Principe 4 — SQL Endpoint verrouillé

Sur le SQL Endpoint du `LH-Banking` :
- Les groupes Insurance n'ont **aucune permission** (ni `Read`, ni `ReadData`)
- Seul le Service Principal utilisé pour créer les shortcuts a `ReadAll` sur les items partagés

---

## 3. Design de la démo — Étapes

### Phase 1 — Création des Lakehouses

#### 3.1 Créer le Lakehouse Banking

```
Workspace : WS-Banking
Item type  : Lakehouse
Name       : LH-Banking
```

Charger les tables Delta suivantes (voir section 4 pour les scripts) :
- `dim_customers`
- `fact_accounts`
- `bridge_ins_customers`

#### 3.2 Créer le Lakehouse Insurance

```
Workspace : WS-Insurance
Item type  : Lakehouse
Name       : LH-Insurance
```

Charger les tables natives :
- `insurance_contracts`
- `insurance_claims`

### Phase 2 — Création des Shortcuts

#### 3.3 Shortcut vers dim_customers

Depuis `LH-Insurance` → `New Shortcut` → `Microsoft OneLake`

```
Source Workspace : WS-Banking
Source Item      : LH-Banking
Source Path      : Tables/dim_customers
Shortcut Name    : sc_dim_customers
```

> ⚠️ Pour que le shortcut fonctionne, le compte ou le Service Principal qui crée  
> le shortcut doit avoir **ReadAll** sur `LH-Banking`.  
> Les utilisateurs Insurance eux-mêmes n'ont PAS accès à WS-Banking.

#### 3.4 Shortcut vers bridge_ins_customers

```
Source Workspace : WS-Banking
Source Item      : LH-Banking
Source Path      : Tables/bridge_ins_customers
Shortcut Name    : sc_bridge_ins_customers
```

### Phase 3 — Création du Semantic Model

#### 3.5 Créer SM-Insurance depuis LH-Insurance

Dans `WS-Insurance` → créer un nouveau Semantic Model sur `LH-Insurance`.

Tables incluses dans le modèle :
| Table | Source | Visible |
|---|---|---|
| `sc_dim_customers` | Shortcut Banking | ✅ (filtrée par RLS) |
| `sc_bridge_ins_customers` | Shortcut Banking | ✅ (filtrée) |
| `insurance_contracts` | Native Insurance | ✅ |
| `insurance_claims` | Native Insurance | ✅ |

Tables **exclues** du modèle (OLS total) :
- `fact_accounts`, `fact_transactions` (ne sont pas shortcutées → non visibles)

#### 3.6 Définir les relations

```
sc_dim_customers[customer_id] ──1:N──► sc_bridge_ins_customers[customer_id]
sc_bridge_ins_customers[customer_id] ──N:1──► insurance_contracts[customer_id]
insurance_contracts[contract_id] ──1:N──► insurance_claims[contract_id]
```

### Phase 4 — Configuration RLS

#### 3.7 Créer le rôle RLS dans SM-Insurance

Dans Fabric Model View → Security → Manage Roles → `+ New Role`

```
Rôle : Insurance_Viewer

Règle DAX sur sc_dim_customers :
[customer_id] IN
    CALCULATETABLE(
        VALUES(sc_bridge_ins_customers[customer_id]),
        USERELATIONSHIP(
            sc_bridge_ins_customers[customer_id],
            insurance_contracts[customer_id]
        )
    )
```

**Alternative plus directe** (si relation active) :

```dax
-- Sur la table sc_dim_customers
RELATED(insurance_contracts[contract_id]) <> BLANK()
```

**Ou via bridge explicite** :

```dax
-- Sur sc_dim_customers
[customer_id] IN VALUES(sc_bridge_ins_customers[customer_id])
```

#### 3.8 Assigner les utilisateurs au rôle RLS

```
Rôle Insurance_Viewer :
→ GRP-Insurance-Analysts (groupe Entra ID)
→ demo.insurance@MngEnvMCAP578215.onmicrosoft.com
```

### Phase 5 — Vérification et tests

#### 3.9 Test "View as role" dans Power BI Desktop

Dans Power BI Desktop (fichier .pbip du Semantic Model Insurance) :

```
Modeling → View as → Insurance_Viewer
```

Vérifier :
- ✅ `sc_dim_customers` ne retourne que les clients avec contrat
- ✅ `insurance_contracts` retourne tous les contrats (pas de filtre supplémentaire nécessaire)
- ❌ Tentative d'accès à `fact_accounts` → table absente du modèle

#### 3.10 Test accès SQL direct (négatif attendu)

Depuis SSMS, connexion au SQL Endpoint de `LH-Banking` avec les credentials d'un user Insurance :

```sql
-- Doit retourner une erreur d'autorisation
SELECT TOP 10 * FROM dim_customers
```

Résultat attendu : `Error 401 - Insufficient permissions`

---

## 4. Modèle de données sample

### 4.1 Table `dim_customers` (Banking)

```sql
CREATE TABLE dim_customers (
    customer_id       VARCHAR(20)  NOT NULL,  -- PK : CUS-0001
    first_name        VARCHAR(50),
    last_name         VARCHAR(50),
    birth_date        DATE,
    city              VARCHAR(100),
    postal_code       VARCHAR(10),
    segment           VARCHAR(20),             -- PREMIUM / STANDARD / YOUNG
    customer_since    DATE,
    email             VARCHAR(100),            -- ⚠️ OLS recommandé sur cette colonne
    phone             VARCHAR(20),             -- ⚠️ OLS recommandé
    monthly_income    DECIMAL(12,2),           -- ⚠️ OLS recommandé
    is_active         BOOLEAN
);
```

> ℹ️ Les colonnes `email`, `phone`, `monthly_income` peuvent être masquées  
> via **OLS (Object-Level Security)** dans le Semantic Model Insurance.

### 4.2 Table `bridge_ins_customers` (Banking — gérée par Banking)

```sql
CREATE TABLE bridge_ins_customers (
    bridge_id           VARCHAR(30)  NOT NULL,
    customer_id         VARCHAR(20)  NOT NULL,  -- FK → dim_customers
    insurance_consent   BOOLEAN,                -- consentement RGPD
    consent_date        DATE,
    sharing_scope       VARCHAR(50)             -- 'INSURANCE_FULL' / 'INSURANCE_BASIC'
);
```

> 🔑 Cette table est **détenue par le Banking**. Pacifica ne peut pas la modifier.  
> Elle représente la liste des clients ayant donné leur accord de partage de données.

### 4.3 Table `insurance_contracts` (Insurance)

```sql
CREATE TABLE insurance_contracts (
    contract_id         VARCHAR(30)  NOT NULL,  -- PK : CTR-PAC-0001
    customer_id         VARCHAR(20)  NOT NULL,  -- FK → dim_customers
    product_code        VARCHAR(20),            -- AUTO / MRH / VIE / PREV
    product_label       VARCHAR(100),
    start_date          DATE,
    end_date            DATE,
    annual_premium      DECIMAL(12,2),
    contract_status     VARCHAR(20),            -- ACTIVE / EXPIRED / SUSPENDED
    advisor_id          VARCHAR(20)
);
```

### 4.4 Table `insurance_claims` (Insurance)

```sql
CREATE TABLE insurance_claims (
    claim_id            VARCHAR(30)  NOT NULL,
    contract_id         VARCHAR(30)  NOT NULL,  -- FK → insurance_contracts
    claim_date          DATE,
    claim_type          VARCHAR(50),
    claim_amount        DECIMAL(12,2),
    claim_status        VARCHAR(20),            -- OPEN / CLOSED / REJECTED
    description         VARCHAR(500)
);
```

### 4.5 Table `fact_accounts` (Banking — NON exposée à l'Assurance)

```sql
CREATE TABLE fact_accounts (
    account_id          VARCHAR(30),
    customer_id         VARCHAR(20),
    account_type        VARCHAR(20),  -- CHECKING / SAVINGS / LOAN
    balance             DECIMAL(15,2),
    open_date           DATE,
    is_active           BOOLEAN
);
```

> ❌ Pas de shortcut vers cette table dans LH-Insurance.

### 4.6 Sample data (CSV pour démo)

#### dim_customers (10 lignes dont 5 avec contrat, 5 sans)

```csv
customer_id,first_name,last_name,birth_date,city,segment,is_active
CUS-0001,Marie,Dupont,1975-03-12,Paris,PREMIUM,true
CUS-0002,Jean,Martin,1988-07-22,Lyon,STANDARD,true
CUS-0003,Sophie,Leroy,1992-11-05,Bordeaux,YOUNG,true
CUS-0004,Pierre,Bernard,1965-01-30,Marseille,PREMIUM,true
CUS-0005,Isabelle,Moreau,1980-09-18,Nantes,STANDARD,true
CUS-0006,Thomas,Simon,1995-04-25,Toulouse,YOUNG,true
CUS-0007,Claire,Laurent,1970-12-08,Nice,PREMIUM,true
CUS-0008,François,Petit,1983-06-14,Strasbourg,STANDARD,true
CUS-0009,Nathalie,Garcia,1991-02-28,Rennes,STANDARD,true
CUS-0010,Luc,Roux,1960-08-03,Grenoble,PREMIUM,true
```

#### bridge_ins_customers (5 clients avec consentement)

```csv
bridge_id,customer_id,insurance_consent,consent_date,sharing_scope
BRG-001,CUS-0001,true,2023-01-15,INSURANCE_FULL
BRG-002,CUS-0002,true,2022-06-30,INSURANCE_BASIC
BRG-003,CUS-0004,true,2021-11-20,INSURANCE_FULL
BRG-004,CUS-0007,true,2024-03-10,INSURANCE_FULL
BRG-005,CUS-0009,true,2023-08-05,INSURANCE_BASIC
```

#### insurance_contracts

```csv
contract_id,customer_id,product_code,product_label,start_date,annual_premium,contract_status
CTR-PAC-001,CUS-0001,MRH,Multirisque Habitation,2023-02-01,380.00,ACTIVE
CTR-PAC-002,CUS-0001,AUTO,Assurance Auto,2022-05-15,820.00,ACTIVE
CTR-PAC-003,CUS-0002,AUTO,Assurance Auto,2022-07-01,650.00,ACTIVE
CTR-PAC-004,CUS-0004,VIE,Assurance Vie,2021-12-01,1200.00,ACTIVE
CTR-PAC-005,CUS-0007,PREV,Prévoyance,2024-04-01,540.00,ACTIVE
CTR-PAC-006,CUS-0009,MRH,Multirisque Habitation,2023-09-01,290.00,ACTIVE
```

---

## 5. Flux d'accès utilisateur Assurance

### 5.1 Scénario : Analyste Pacifica ouvre un rapport Power BI

```
1. L'analyste Pacifica (demo.insurance@...) se connecte au service Power BI
   │
2. Il accède au workspace WS-Insurance
   │    ✅ Il a le rôle Viewer sur ce workspace
   │    ❌ Il n'a aucun accès à WS-Banking
   │
3. Il ouvre le rapport "Rapport_Assurance_Clients"
   │    Ce rapport est connecté à SM-Insurance en mode Direct Lake
   │
4. Power BI applique le RLS : rôle Insurance_Viewer
   │    La règle DAX filtre sc_dim_customers :
   │    → Retourne uniquement CUS-0001, CUS-0002, CUS-0004, CUS-0007, CUS-0009
   │
5. Le moteur Direct Lake charge les données depuis OneLake
   │    → sc_dim_customers shortcut → LH-Banking/dim_customers
   │    → Seules les 5 lignes autorisées sont retournées au modèle
   │
6. L'analyste voit :
   ✅ Marie Dupont — 2 contrats (MRH + Auto) — Paris — PREMIUM
   ✅ Jean Martin — 1 contrat (Auto) — Lyon — STANDARD
   ✅ Pierre Bernard — 1 contrat (Vie) — Marseille — PREMIUM
   ✅ Claire Laurent — 1 contrat (Prévoyance) — Nice — PREMIUM
   ✅ Nathalie Garcia — 1 contrat (MRH) — Rennes — STANDARD
   
   ❌ Thomas Simon (CUS-0006) — pas de contrat assurance → invisible
   ❌ François Petit (CUS-0008) — pas de consentement → invisible
   ❌ fact_accounts — table absente du modèle → inaccessible
```

### 5.2 Requête DAX générée (transparente pour l'utilisateur)

```dax
-- Ce que Power BI exécute en interne quand l'analyste filtre sur le segment PREMIUM :
EVALUATE
CALCULATETABLE(
    SUMMARIZECOLUMNS(
        sc_dim_customers[customer_id],
        sc_dim_customers[first_name],
        sc_dim_customers[last_name],
        sc_dim_customers[segment],
        "Nb Contrats", COUNTROWS(insurance_contracts)
    ),
    sc_dim_customers[segment] = "PREMIUM",
    -- RLS injecté automatiquement :
    sc_dim_customers[customer_id] IN VALUES(sc_bridge_ins_customers[customer_id])
)
```

Résultat : uniquement **Marie Dupont** et **Pierre Bernard** et **Claire Laurent** (PREMIUM avec contrat).

---

## 6. Extension — Assurance Vie / Gestion de Patrimoine

### 6.1 Use case supplémentaire : Wealth Management

La filiale **Gestion de Patrimoine CA** (Amundi / BFT) a besoin de :
- Les clients PREMIUM avec un contrat Assurance Vie actif
- Leur tranche de revenus (buckétisée, pas le montant exact)
- Pas d'accès aux contrats AUTO ou MRH

### 6.2 Architecture étendue

```
WS-Banking (LH-Banking)
    │
    ├── Shortcut dans LH-Insurance (comme avant)
    │
    └── Nouveau shortcut dans LH-Wealth :
        • sc_dim_customers (même source)
        • sc_bridge_wealth_customers (nouvelle table Banking)

WS-Wealth (LH-Wealth) [NOUVEAU]
    ├── wealth_portfolios
    ├── wealth_mandates
    ├── sc_dim_customers  (shortcut Banking)
    └── sc_bridge_wealth_customers (shortcut Banking)
    
SM-Wealth
    └── Rôle Wealth_Advisor :
        DAX : [customer_id] IN VALUES(sc_bridge_wealth_customers[customer_id])
            AND [segment] = "PREMIUM"
```

### 6.3 Réutilisation du pattern sécurité

```
Pattern générique réutilisable :
┌─────────────────────────────────────────────────────┐
│  Pour chaque domaine filiale :                       │
│                                                      │
│  1. Banking maintient une bridge table dédiée :      │
│     bridge_[domaine]_customers                       │
│     → Seuls les clients autorisés par le Banking     │
│                                                      │
│  2. Le domaine crée un shortcut vers :               │
│     - dim_customers (source de vérité client)        │
│     - bridge_[domaine]_customers (liste blanche)     │
│                                                      │
│  3. Le Semantic Model applique :                     │
│     RLS : customer_id IN bridge table                │
│     OLS : masquer colonnes sensibles si besoin       │
│                                                      │
│  4. Les workspaces restent isolés                    │
│     → Pas de croisement de données inter-domaines    │
└─────────────────────────────────────────────────────┘
```

### 6.4 OLS — Masquage des colonnes sensibles pour Wealth

Dans `SM-Wealth`, configurer l'OLS sur `sc_dim_customers` :

| Colonne | Wealth_Advisor | Insurance_Viewer |
|---|---|---|
| `customer_id` | ✅ Visible | ✅ Visible |
| `first_name` | ✅ Visible | ✅ Visible |
| `last_name` | ✅ Visible | ✅ Visible |
| `segment` | ✅ Visible | ✅ Visible |
| `city` | ✅ Visible | ✅ Visible |
| `email` | ❌ Masqué (OLS) | ❌ Masqué (OLS) |
| `phone` | ❌ Masqué (OLS) | ❌ Masqué (OLS) |
| `monthly_income` | ✅ Buckétisé (mesure DAX) | ❌ Masqué (OLS) |
| `birth_date` | ✅ Visible (pour produits) | ✅ Visible |

**Mesure DAX pour buckétiser les revenus (Wealth uniquement)** :

```dax
Income Bracket =
SWITCH(
    TRUE(),
    sc_dim_customers[monthly_income] < 2000,   "< 2K€",
    sc_dim_customers[monthly_income] < 4000,   "2K - 4K€",
    sc_dim_customers[monthly_income] < 7000,   "4K - 7K€",
    sc_dim_customers[monthly_income] < 10000,  "7K - 10K€",
                                               "> 10K€"
)
```

---

## 7. Récapitulatif des bonnes pratiques sécurité

### 🔒 Checklist sécurité Fabric multi-domaines

```
✅ 1. Un workspace par domaine métier (pas de workspace partagé)
✅ 2. Les utilisateurs d'un domaine n'ont JAMAIS accès au workspace source
✅ 3. Les shortcuts sont créés par un SP technique (pas par les users)
✅ 4. Seules les tables nécessaires sont shortcutées (surface minimale)
✅ 5. RLS défini sur le Semantic Model — pas au niveau Lakehouse
✅ 6. OLS configuré pour masquer les colonnes PII non nécessaires
✅ 7. SQL Endpoint du Lakehouse source : aucun accès aux groups filiales
✅ 8. La bridge table est maintenue par le domaine Banking (pas la filiale)
✅ 9. Audit des accès activé (Fabric Admin Portal → Activity Log)
✅ 10. Revue trimestrielle des membres des rôles RLS
```

### ⚠️ Anti-patterns à éviter

```
❌ Donner accès au workspace Banking à des users Insurance "pour faciliter"
❌ Créer un shortcut vers toutes les tables Banking (principe moindre privilège)
❌ Utiliser des rapports Power BI sans RLS comme seule couche de sécurité
❌ Partager le SQL Endpoint comme source de données sans contrôle d'accès
❌ Laisser des notebooks Fabric avec accès aux Lakehouses source sans audit
❌ Utiliser des comptes personnels pour créer les shortcuts (utiliser des SP)
```

---

## 8. Story client (Storytelling démo)

### 🎬 Script démo client — 20 minutes

**Contexte narratif** :
> *"Imaginez que vous êtes chez Crédit Agricole Île-de-France. La filiale Pacifica  
> a besoin d'accéder à certaines données clients pour personnaliser ses offres d'assurance.  
> Comment partager ces données en toute sécurité, sans exposer l'ensemble du portefeuille clients ?"*

---

#### Acte 1 — Le problème (2 min)

> *"Aujourd'hui, sans Fabric, deux approches classiques : soit on duplique les données  
> (coûteux, risque de désynchronisation, problème RGPD), soit on donne un accès direct  
> à la base Banking (trop large, risque réglementaire).*
>
> *Avec Microsoft Fabric et OneLake, il existe une troisième voie."*

---

#### Acte 2 — L'architecture (5 min)

Montrer le diagramme d'architecture :

> *"Deux workspaces totalement isolés. Pacifica ne peut même pas voir le workspace Banking.  
> Mais grâce aux shortcuts OneLake, le Lakehouse Pacifica peut lire certaines tables Banking  
> comme si elles étaient locales — sans copie de données."*

Démontrer dans Fabric :
1. Ouvrir `WS-Banking` → montrer `LH-Banking` avec ses tables
2. Ouvrir `WS-Insurance` → montrer les shortcuts `sc_dim_customers`
3. Montrer que les shortcuts pointent vers Banking mais sont dans Insurance

---

#### Acte 3 — La sécurité en action (8 min)

Démonstration 1 — Accès Banking (admin) :

> *"En tant qu'admin Banking, je vois tous les clients : 10 clients dans notre démo."*

```
Connexion : demo.admin@MngEnvMCAP578215.onmicrosoft.com
Résultat : 10 lignes dans dim_customers
```

Démonstration 2 — Accès Insurance (analyste Pacifica) :

> *"En tant qu'analyste Pacifica, je me connecte au rapport Insurance. Regardez : je ne vois  
> que 5 clients — ceux qui ont un contrat actif ET qui ont donné leur consentement.*
>
> *Les 5 autres clients ? Invisibles. Comme s'ils n'existaient pas pour Pacifica."*

```
Connexion : demo.insurance@MngEnvMCAP578215.onmicrosoft.com
Résultat : 5 lignes dans sc_dim_customers (RLS actif)
```

Démonstration 3 — Tentative de contournement :

> *"Maintenant, l'analyste essaie d'accéder directement au SQL Endpoint Banking..."*

```sql
-- Depuis SSMS avec les credentials Insurance
SELECT * FROM LH-Banking.dbo.dim_customers
-- → Error: The principal does not have READ permission
```

> *"Impossible. La sécurité est en couches : le RLS protège le Semantic Model,  
> et les permissions Fabric protègent la couche SQL directe."*

---

#### Acte 4 — Extension Wealth (3 min)

> *"Le même pattern peut être répliqué pour la Gestion de Patrimoine, pour le Crédit Conso,  
> pour les Marchés de Capitaux. Chaque filiale a son propre workspace, ses propres shortcuts  
> ciblés, son propre modèle de sécurité.*
>
> *C'est l'architecture **Data Mesh** de Microsoft Fabric : des domaines autonomes,  
> une seule source de vérité, une gouvernance centralisée."*

---

#### Acte 5 — Conclusion et recommandations (2 min)

| Critère | Réponse |
|---|---|
| Duplication de données | ❌ Aucune (OneLake shortcuts) |
| Isolation des domaines | ✅ Workspaces séparés |
| Filtrage métier | ✅ RLS sur Semantic Model |
| Masquage PII | ✅ OLS sur colonnes sensibles |
| Scalabilité | ✅ Pattern réplicable par filiale |
| Conformité RGPD | ✅ Consentement tracé dans bridge table |
| Audit des accès | ✅ Activity Log Fabric |

> *"Microsoft Fabric n'est pas seulement une plateforme analytique.  
> C'est une plateforme de gouvernance des données, conçue pour les groupes bancaires  
> multi-entités comme Crédit Agricole."*

---

*Document généré par GitHub Copilot — Architecture Microsoft Fabric*  
*Référence projet : CA-GIP — Démonstration Gouvernance Data*
