# Mail Client — Problématique SSIS & Recommandations

---

## 📧 Mail à envoyer

**Objet :** Retour sur la problématique de délégation SSIS — Recommandations et prochaines étapes

Bonjour,

Suite à notre réunion concernant les problèmes de délégation rencontrés avec SSIS, je vous fais un retour consolidé avec nos recommandations.

### Rappel du contexte

Nous avons identifié plusieurs points bloquants liés à l'authentification et à la délégation dans l'architecture actuelle :

- **SSIS ne supporte pas la délégation contrainte Kerberos** (limitation confirmée par Microsoft). Cela empêche SSIS de propager l'identité de l'utilisateur vers des ressources distantes (bases de données, partages réseau) lorsqu'un compte AD en délégation contrainte est utilisé.
- **L'accès multi-bases de données** via SQL Agent sur le même serveur a montré des limitations.
- **Les droits traversants** sur les répertoires entre le partage réseau et le répertoire cible posent un problème, notamment dans la perspective d'une migration d'infrastructure de stockage.

### Solution de contournement actuelle

Un compte SQL Server en authentification SQL a été mis en place comme contournement temporaire. Cette solution fonctionne mais présente des contraintes :
- Nécessité de stocker et sécuriser les credentials (mot de passe)
- Pas d'intégration avec l'annuaire Active Directory
- Rotation manuelle des mots de passe à prévoir
- Traçabilité limitée par rapport à une authentification intégrée Windows

**Cette solution est acceptable à court terme**, à condition de la sécuriser correctement (voir recommandations ci-dessous).

### Notre recommandation : renforcer l'orchestration via Airflow

Après analyse des différentes options, nous recommandons de **capitaliser sur Airflow** comme couche d'orchestration principale pour résoudre durablement les problèmes de délégation. Cette approche est déjà partiellement en place avec la gestion des tickets Kerberos et présente les avantages suivants :

1. **Gestion native de l'authentification Kerberos** — Airflow peut obtenir et renouveler les tickets Kerberos, ce qui résout le problème du double hop sans dépendre de la délégation contrainte de SSIS.

2. **Orchestration centralisée** — Un seul point de contrôle pour l'ensemble des flux, avec une visibilité complète sur les exécutions, les erreurs et les dépendances.

3. **Pas de dépendance au mécanisme de délégation SSIS** — En déléguant l'authentification à Airflow, on contourne définitivement la limitation de SSIS.

4. **Compatibilité avec l'infrastructure existante** — Solution on-premise, pas de dépendance cloud, compatible avec votre environnement Active Directory et vos partages réseau actuels.

### Sécurisation de la solution de contournement SQL (court terme)

En attendant le déploiement complet de la solution Airflow, nous recommandons les mesures suivantes pour l'authentification SQL :
- Stocker les credentials dans le **catalogue SSIS (SSISDB)** avec chiffrement des paramètres d'environnement
- Mettre en place une **rotation du mot de passe tous les 90 jours** au minimum
- **Restreindre les droits** du compte SQL au strict nécessaire (principe du moindre privilège)
- **Auditer les connexions** via ce compte dans les logs SQL Server

### Prochaines étapes

1. **Collecte des informations techniques** — Nous avons besoin des versions exactes de SSIS, SQL Server et de l'OS pour affiner nos recommandations. Merci de nous les transmettre.

2. **Ouverture d'un case support Microsoft** — Nous prévoyons d'ouvrir un ticket auprès de Microsoft pour :
   - Clarifier le comportement des droits traversants / héritage sur les partages réseau
   - Confirmer s'il existe une roadmap pour corriger la limitation de délégation SSIS
   - Obtenir l'architecture de référence recommandée par Microsoft pour ce type de scénario

3. **Plan de déploiement Airflow** — Formalisation d'un plan pour étendre la gestion Kerberos via Airflow à l'ensemble des flux concernés.

Je reste à votre disposition pour en discuter.

Cordialement,  
Julien

---

## 📋 Recommandation détaillée — Architecture Airflow

### Architecture cible

```
┌─────────────────────────────────────────────────────┐
│                    AIRFLOW                           │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │  Scheduler   │  │   Workers    │  │  Metadata  │ │
│  │             │  │  (Executors) │  │    DB      │ │
│  └─────────────┘  └──────┬───────┘  └────────────┘ │
│                          │                          │
│         ┌────────────────┼────────────────┐         │
│         │     Kerberos Ticket Manager     │         │
│         │   (kinit / keytab automatisé)   │         │
│         └────────────────┬────────────────┘         │
└──────────────────────────┼──────────────────────────┘
                           │
              Tickets Kerberos valides
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
   ┌────────────┐  ┌────────────┐  ┌──────────────┐
   │ SQL Server │  │ SQL Server │  │   Partages   │
   │   BDD 1    │  │   BDD 2    │  │    Réseau    │
   │ (Auth Win) │  │ (Auth Win) │  │   (CIFS/SMB) │
   └────────────┘  └────────────┘  └──────────────┘
```

### Gestion Kerberos dans Airflow

#### 1. Configuration du keytab

Le compte de service Airflow doit disposer d'un **keytab** pour s'authentifier automatiquement :

```ini
# airflow.cfg
[kerberos]
keytab = /etc/security/keytabs/airflow.service.keytab
principal = airflow/hostname@DOMAINE.LOCAL
reinit_frequency = 3600
kinit_path = kinit
ccache = /tmp/airflow_krb5_ccache
```

#### 2. Renouvellement automatique des tickets

Airflow intègre un **ticket renewer** qui renouvelle automatiquement les tickets avant expiration :
- Configurer `reinit_frequency` selon la politique Kerberos du domaine
- S'assurer que le keytab a les droits de lecture uniquement par le compte de service Airflow
- Surveiller les logs de renouvellement pour détecter les échecs

#### 3. Groupes d'accès pour le double hop

| Groupe AD | Rôle | Ressources autorisées |
|-----------|------|-----------------------|
| `GRP_AIRFLOW_SQL_READ` | Lecture BDD | Bases de données sources |
| `GRP_AIRFLOW_SQL_WRITE` | Écriture BDD | Bases de données cibles |
| `GRP_AIRFLOW_SHARE_ACCESS` | Accès partages | Répertoires réseau (données entrantes/sortantes) |

Le compte de service Airflow doit être membre de ces groupes pour permettre l'accès transparent via Kerberos.

#### 4. DAGs SSIS dans Airflow

Pour les packages SSIS existants, utiliser l'opérateur `BashOperator` ou `MsSqlOperator` :

```python
# Exemple de DAG appelant un package SSIS via dtexec
from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime

with DAG(
    dag_id="ssis_package_execution",
    schedule_interval="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
) as dag:

    run_package = BashOperator(
        task_id="run_ssis_package",
        bash_command=(
            'dtexec /ISServer '
            '"\\SSISDB\\MonProjet\\MonPackage.dtsx" '
            '/Server "SQLSERVER01" '
            '/Par "$ServerOption::SYNCHRONIZED(Boolean)";True'
        ),
    )
```

#### 5. Migration progressive

| Phase | Périmètre | Durée estimée |
|-------|-----------|---------------|
| **Phase 1** | Validation de la gestion Kerberos sur les flux existants déjà dans Airflow | 2 semaines |
| **Phase 2** | Migration des flux SSIS critiques vers des DAGs Airflow avec auth Kerberos | 4-6 semaines |
| **Phase 3** | Décommissionnement des contournements SQL auth et passage complet en auth intégrée | 2 semaines |
| **Phase 4** | Documentation, transfert de compétences et mise en supervision | 1 semaine |

### Bénéfices attendus

- ✅ **Élimination du problème de délégation SSIS** — Airflow gère l'authentification directement
- ✅ **Suppression des credentials SQL stockés** — Plus de mots de passe à gérer/rotater
- ✅ **Audit centralisé** — Toutes les connexions passent par le compte de service AD, tracé dans les logs AD et SQL
- ✅ **Infrastructure on-premise** — Aucune dépendance cloud, compatible avec l'existant
- ✅ **Évolutivité** — Airflow permet d'ajouter facilement de nouveaux flux et connecteurs

### Points d'attention

- ⚠️ Le **keytab** doit être sécurisé (permissions restrictives, stockage protégé)
- ⚠️ Prévoir une **supervision du renouvellement Kerberos** (alerte si échec de kinit)
- ⚠️ La **problématique des droits traversants** sur les partages reste à clarifier avec Microsoft (case support)
- ⚠️ Les packages SSIS complexes peuvent nécessiter une **réécriture partielle** pour être orchestrés via Airflow

---

*Document préparé le 3 avril 2026 — Julien*
