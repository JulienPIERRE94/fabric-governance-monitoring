# Guide de gouvernance — Power BI Report Server (On-Prem) vs Power BI Service

**Date :** 30 avril 2026  
**Public :** DSI, équipe BI, RSSI, exploitation, métiers  
**Objectif :** définir une gouvernance robuste pour un environnement **Power BI Report Server (PBIRS)** on-prem, en clarifiant les différences majeures avec **Power BI Service**.

---

> ## ⚠️ Point d'attention critique — PBIRS n'impose AUCUNE limite de rafraîchissement
>
> Contrairement à **Power BI Service** qui plafonne strictement le nombre de rafraîchissements planifiés ([8/jour en shared capacity, 48/jour en Premium/PPU/Fabric](https://learn.microsoft.com/en-us/power-bi/connect-data/refresh-data#data-refresh)) et impose des quotas par capacité, **Power BI Report Server n'applique aucun garde-fou natif** :
>
> - un utilisateur peut planifier un refresh **toutes les minutes** sur un rapport volumineux,
> - les rafraîchissements **interactifs** (`Refresh` depuis le portail) sont illimités,
> - rien n'empêche la multiplication des subscriptions et des plans concurrents,
> - en l'absence de quota, **un seul rapport mal configuré peut saturer le serveur** (CPU, RAM, IOPS SQL) et dégrader l'expérience de tous les utilisateurs,
> - **limite officielle PBIRS** : un modèle import ne peut pas dépasser **2 Go** ([source](https://learn.microsoft.com/en-us/power-bi/report-server/scheduled-refresh#data-model-size-limit)) — au-delà, le refresh échoue (`The length of the result exceeds the length limit (2GB)`).
>
> **Conséquence :** la gouvernance PBIRS doit obligatoirement intégrer un **encadrement explicite des rafraîchissements** (cf. section 6.7) : standards de planification, supervision des durées, plafonnement par convention, alerting sur les dérives. Sans cela, le serveur subit la charge sans mécanisme de régulation.

---

## 1) Résumé exécutif

Si votre client exploite **Power BI Report Server on-prem**, il gagne en contrôle de l’infrastructure et des données, mais il récupère aussi plus de responsabilités :

- capacité et performance,
- **pilotage des rafraîchissements (aucune limite native, cf. ⚠️ ci-dessus)**,
- sauvegardes / PRA,
- patching et sécurité OS/SQL/IIS,
- supervision et audits,
- gestion fine des accès.

À l’inverse, **Power BI Service** apporte davantage de services managés (SaaS), mais avec un cadre de gouvernance orienté cloud (workspaces, tenant settings, capacités Fabric/Premium, etc.).

---

## 2) Principales différences de gouvernance

| Domaine | Power BI Report Server (On-Prem) | Power BI Service (Cloud) | Impact gouvernance |
|---|---|---|---|
| Hébergement | Infrastructure client (VM/physique) | Microsoft (SaaS) | On-prem : responsabilité complète d’exploitation |
| Mises à jour | Manuelles (versionning PBIRS + SQL Server) | Continue (Microsoft) | On-prem : cycle de patch à planifier/tester |
| Authentification | AD/Kerberos/NTLM principalement | Entra ID (Azure AD), SSO cloud | On-prem : dépendance forte à l’AD et SPN/Kerberos |
| Publication / collaboration | Portail PBIRS par dossiers | Workspaces, Apps, partage cloud | Modèle de collaboration plus limité en on-prem |
| Self-service | Plus restreint | Plus riche (Fabric, partage, dataflows, etc.) | Arbitrer centralisation vs autonomie |
| Rafraîchissement données | **Aucune limite native** — fréquence et nombre libres | 8/j (Pro), 48/j (Premium/PPU), quotas par capacité | **PBIRS : risque de saturation à encadrer par gouvernance** |
| Orchestration refresh | Piloté localement (jobs SQL Agent) | Services cloud + gateways gérés | On-prem : orchestration/monitoring à construire |
| Sécurité réseau | Contrôle total (segmentation interne) | Exposition cloud maîtrisée via policies | On-prem : responsabilité firewall, proxy, certificats |
| Audit / logs | À structurer localement | Intégration M365 / Purview / admin APIs | On-prem : prévoir une chaîne d’audit dédiée |
| PRA / sauvegarde | Entièrement à charge client | Résilience SaaS Microsoft | On-prem : tester régulièrement la restauration |
| Roadmap fonctionnalités | Souvent en décalage vs cloud | Fonctionnalités plus rapides | Gérer attentes métiers sur les features |

---

## 3) Modèle de gouvernance recommandé (PBIRS)

## 3.1 Rôles et responsabilités (RACI simplifié)

- **Propriétaire BI (Métier/IT)** : priorisation des usages, validation des KPI.
- **Administrateur PBIRS** : sécurité portail, dossiers, subscriptions, standards de publication.
- **Administrateur SQL Server** : base `ReportServer`, jobs, performances, sauvegardes.
- **Administrateur Système** : OS, certificats, patching, monitoring infra.
- **RSSI / IAM** : modèle d’habilitation AD, revues d’accès périodiques.
- **Équipe Dev BI** : qualité des modèles et rapports, documentation, release notes.

## 3.2 Environnements

Minimum recommandé :

1. **DEV** (itération rapide)
2. **TEST/UAT** (validation métier + non-régression)
3. **PROD** (stabilité, traçabilité)

> Éviter la publication directe en PROD depuis les postes développeurs.

## 3.3 Processus de changement

- Demande de changement (ticket)
- Revue technique (performance, sécurité, naming)
- Validation métier
- Déploiement planifié (fenêtre de changement)
- Contrôle post-déploiement + retour arrière documenté

---

## 4) Bonnes pratiques (Do)

## 4.1 Sécurité et accès

- Structurer les accès par **groupes AD** (jamais utilisateur par utilisateur).
- Appliquer le **moindre privilège** (lecture seule par défaut).
- Séparer clairement rôles de dev, admin, exploitation.
- Activer TLS proprement (certificats valides, protocoles durcis).
- Mettre en place une revue trimestrielle des habilitations.

## 4.2 Architecture et exploitation

- Dimensionner PBIRS avec des tests de charge réalistes.
- Isoler les sources critiques (SQL, fichiers, API internes) et monitorer les latences.
- Sauvegarder **base ReportServer**, clés de chiffrement, et artefacts de déploiement.
- Documenter un PRA avec test de restauration au moins semestriel.
- Superviser : disponibilité portail, temps de rendu, échecs de refresh/subscription.

## 4.3 Qualité des rapports

- Standardiser conventions de nommage (dossiers, rapports, datasets, paramètres).
- Créer un modèle de page (charte visuelle, navigation, filtres).
- Limiter le volume de visuels par page ; privilégier lisibilité et performance.
- Mettre des owners explicites par rapport (métier + IT).
- Versionner les fichiers `.pbix`/`.rdl` et conserver les notes de release.

## 4.4 Cycle de vie

- Définir SLA/SLO (disponibilité, délai correction incident, fraîcheur des données).
- Mettre en place une matrice de criticité des rapports.
- Revue semestrielle : rapports obsolètes, duplication, dette technique.
- Politique de rétention/archivage des contenus inutilisés.

---

## 5) Mauvaises pratiques (Don’t)

- Donner des droits d’administration trop larges « pour aller plus vite ».
- Publier en production sans validation fonctionnelle/performance.
- Laisser des connexions data avec comptes techniques non maîtrisés.
- Mélanger contenu critique et expérimental dans le même dossier de PROD.
- Ignorer les mises à jour PBIRS/SQL/OS pendant de longues périodes.
- Ne pas tester la restauration (backup « théorique »).
- Construire des rapports « monolithes » trop lourds et difficiles à maintenir.

---

## 6) Points d’attention spécifiques PBIRS

1. **Écart fonctionnel vs Power BI Service**  
   Certaines fonctionnalités cloud peuvent ne pas exister ou arriver plus tard en PBIRS.

2. **Dépendance AD/Kerberos**  
   Les problèmes SPN/double hop peuvent impacter les sources distantes.

3. **Gestion de capacité**  
   Sans capacité cloud élastique, la saturation serveur est plus rapide en pics d’usage.

4. **Audit centralisé**  
   Concevoir tôt une stratégie de logs (corrélation portail, SQL, OS, proxy).

5. **Patch management**  
   Formaliser un runbook de patch (pré-prod → prod, tests de non-régression).

6. **Gouvernance des données**  
   Clarifier la « source de vérité » des KPI et la propriété des jeux de données.

## 6.7 ⚠️ Encadrement des rafraîchissements (POINT CRITIQUE PBIRS)

**PBIRS ne pose aucune limite technique** sur la fréquence ou le nombre de rafraîchissements (planifiés ou interactifs). C'est à la gouvernance — et **uniquement à elle** — d'imposer un cadre. Sans cela, un utilisateur peut, en quelques clics, déclencher des refresh toutes les minutes et saturer le serveur.

### Règles de gouvernance à formaliser

| Règle | Recommandation par défaut |
|---|---|
| Fréquence minimale entre 2 refresh planifiés d'un même rapport | ≥ 15 minutes (opérationnel), ≥ 1 heure (analytique) |
| Nombre maximum de refresh planifiés par rapport / jour | 24 (opérationnel), 4 (analytique), 1 (rapport historique) |
| Plage horaire des refresh « lourds » | Heures creuses (22h–06h), jamais en pic métier |
| Durée maximale tolérée d'un refresh | < 30 min ; au-delà → revue d'optimisation obligatoire |
| Volume max d'un modèle import | 1 à 2 Go (au-delà → DirectQuery / agrégats / dataflow amont) |
| Subscriptions par rapport | Plafond à définir (ex. 10) avec validation IT au-delà |
| Refresh interactif depuis le portail | Traçage + alerte si > N appels/heure par utilisateur |
| Sérialisation | Éviter > 5 refresh concurrents sur la même source SQL critique |

### Mise en œuvre pratique

1. **Inventorier** la table `dbo.Schedule` + `dbo.Subscriptions` + `dbo.ExecutionLog` de la base `ReportServer` (planifications actuelles, durées, fréquences).
2. **Cartographier** les rapports par **classe de criticité** (opérationnel temps réel / analytique / historique) et associer la fréquence cible à chaque classe.
3. **Détecter automatiquement les dérives** via une requête récurrente sur `ExecutionLog` :
   - rapports avec > N refresh / jour,
   - durées de rendu supérieures au seuil,
   - utilisateurs générant un volume anormal de rafraîchissements.
4. **Communiquer** : afficher dans la documentation du portail les règles de fréquence, et notifier les owners en cas d'écart.
5. **Industrialiser le contrôle** : un job SQL Agent quotidien qui désactive (ou flag) les schedules non conformes (par convention, pas par contrainte technique).
6. **Capacité** : dimensionner le serveur en partant du *pic* de concurrence observé, et conserver une marge ≥ 30 %.

### Indicateurs à surveiller

- Nombre de rafraîchissements / heure (total + top 10 rapports)
- Durée P95 d'un refresh (par rapport et par source de données)
- Taux d'échec des refresh planifiés
- Concurrence max observée (refresh simultanés)
- Refresh hors plage horaire conventionnée
- Rapports en écart vs règle de fréquence (« abus de refresh »)

> **À retenir :** en Power BI Service, Microsoft impose le cadre. En PBIRS, **c'est vous qui devez le construire**. C'est l'un des risques de gouvernance les plus sous-estimés lors d'une migration ou d'une mise en production PBIRS.

### 📖 Recommandations officielles Microsoft (sourcées)

Extraits directs de la documentation Microsoft applicables à PBIRS :

- **Limite stricte de 2 Go par modèle import** — *« The data model loaded into the internal Analysis Services engine during a scheduled refresh has a maximum size of 2,000 MB (2GB). This maximum size can't be configured. »*  
  → [Power BI Report Server — Considerations and limitations → Data model size limit](https://learn.microsoft.com/en-us/power-bi/report-server/scheduled-refresh#data-model-size-limit)
- **L'instance Analysis Services interne consomme la mémoire du serveur** : *« Analysis Services may be consuming memory alongside the report server »* → dimensionner explicitement.  
  → [Memory limits](https://learn.microsoft.com/en-us/power-bi/report-server/scheduled-refresh#memory-limits) • [Memory Properties (SSAS)](https://learn.microsoft.com/en-us/sql/analysis-services/server-properties/memory-properties)
- **Architecture refresh PBIRS** : SQL Server Agent + queue dans la base `ReportServer` + Analysis Services interne + Power Query mashup engine.  
  → [How scheduled refresh works](https://learn.microsoft.com/en-us/power-bi/report-server/scheduled-refresh#how-this-works)
- **Refresh impossible** dans certains cas (à documenter dans la gouvernance) : Live connection AS, DirectQuery, sources dynamiques, OAuth (Google Analytics, Salesforce…), chemins de fichier locaux non partagés.  
  → [When scheduled refresh can't be used](https://learn.microsoft.com/en-us/power-bi/report-server/scheduled-refresh#when-scheduled-refresh-cant-be-used)
- **Best practices Microsoft** (transposables à PBIRS) :
  - planifier les refresh **en dehors des heures de pic**,
  - utiliser **incremental refresh** dès qu'un modèle dépasse 1 Go ou prend plusieurs heures,
  - n'inclure que les tables/colonnes utilisées, optimiser le M et limiter les calculs DAX coûteux (itération ligne à ligne),
  - **séparer les gateways** (Import vs DirectQuery/Live) pour ne pas pénaliser les requêtes utilisateurs pendant un refresh,
  - garantir que les notifications d'échec arrivent bien dans la boîte d'un owner identifié.  
  → [Data refresh — Best practices](https://learn.microsoft.com/en-us/power-bi/connect-data/refresh-data#best-practices)

---

## 7) Matrice de décision rapide : PBIRS vs Service

Utiliser **PBIRS** si :

- contraintes réglementaires fortes on-prem,
- données non exposables cloud,
- besoin de contrôle infra complet.

Utiliser **Power BI Service** si :

- priorité à l’innovation fonctionnelle,
- collaboration/self-service à grande échelle,
- volonté de réduire la charge d’exploitation infra.

Approche fréquente : **modèle hybride** (socle réglementé on-prem + usages collaboratifs cloud maîtrisés).

---

## 8) Checklist opérationnelle (90 jours)

## 0–30 jours

- Inventaire des rapports, owners, criticité, dépendances data.
- Cartographie des accès AD et nettoyage des droits.
- Mise en place des sauvegardes + export clé de chiffrement.
- Définition standards de nommage et dossier PROD.

## 31–60 jours

- Chaîne DEV/TEST/PROD + procédure de release.
- Tableau de bord d’exploitation (disponibilité, erreurs, latence).
- Plan de patching trimestriel avec pré-prod.
- Revue sécurité IAM/RSSI.

## 61–90 jours

- Test PRA complet (restauration + validation fonctionnelle).
- Revue de performance (top rapports lents, optimisations).
- Rationalisation du portefeuille de rapports.
- Validation des SLA/SLO avec métiers.

---

## 9) Indicateurs de pilotage recommandés

- Taux de disponibilité PBIRS
- Temps moyen de rendu (P50/P95)
- Taux d’échec de refresh/subscriptions
- Nombre de rapports sans owner
- Nombre d’incidents liés aux droits
- Délai moyen de mise en production
- Taux de réussite des restaurations testées

---

## 10) Checklist de monitoring — Portail PBIRS (prête à déployer)

## 10.1 Disponibilité (uptime)

- [ ] Sonde HTTP(S) sur les endpoints : `/reports` et `/reportserver`
- [ ] Vérification certificat TLS (expiration, chaîne de confiance)
- [ ] Alerte immédiate si indisponibilité > 2 minutes
- [ ] Vérification DNS/routage depuis au moins 2 points de supervision

## 10.2 Performance applicative

- [ ] Temps de réponse portail (P50/P95)
- [ ] Taux d’erreurs HTTP (4xx/5xx)
- [ ] Suivi des erreurs d’authentification (Kerberos/NTLM)
- [ ] Alerte si latence P95 > seuil convenu (ex. 3 secondes)

## 10.3 Santé serveur (OS/IIS/SQL)

- [ ] CPU, RAM, disque (IOPS, latence), espace libre
- [ ] Santé services Windows liés à PBIRS
- [ ] Logs IIS + logs applicatifs centralisés
- [ ] Supervision SQL de la base `ReportServer` (croissance, blocages, sauvegardes)

## 10.4 Exécutions, abonnements et **rafraîchissements**

- [ ] Taux de succès/échec des subscriptions
- [ ] Durée moyenne de rendu des rapports
- [ ] Détection des timeouts et erreurs récurrentes
- [ ] Rapport hebdomadaire des top N rapports lents
- [ ] **Nombre de refresh par rapport / jour** (alerte si dépassement de la règle 6.7)
- [ ] **Concurrence des refresh** (jamais > N en parallèle sur sources critiques)
- [ ] **Refresh interactifs abusifs** par utilisateur (top 10 hebdomadaire)
- [ ] **Schedules hors plage horaire** convenue
- [ ] Job de contrôle quotidien des `dbo.Schedule` non conformes

## 10.5 Gouvernance opérationnelle

- [ ] Runbook d’incident (N1/N2/N3) validé
- [ ] Tableau de bord d’exploitation partagé (IT + BI)
- [ ] Test PRA/restauration au moins 2 fois par an
- [ ] Revue mensuelle des alertes et ajustement des seuils

---

## 11) Solution pour identifier les portails de rapports PBIRS

Objectif : recenser rapidement toutes les URL de portails PBIRS on-prem (y compris instances oubliées).

### Approche recommandée

1. **Inventaire des serveurs cibles**  
   Partir de la CMDB + serveurs SQL/BI connus + serveurs Windows portant des rôles BI.

2. **Test automatique des endpoints standards**  
   Sur chaque hôte, tester :
   - `https://<serveur>/reports`
   - `http://<serveur>/reports`
   - `https://<serveur>/reportserver`
   - `http://<serveur>/reportserver`

3. **Validation applicative**  
   Confirmer PBIRS via :
   - code HTTP attendu,
   - titre de page / entête serveur,
   - présence d’éléments propres au portail PBIRS.

4. **Consolidation**  
   Conserver un registre unique : URL, environnement (DEV/TEST/PROD), owner, criticité, méthode d’auth, statut supervision.

### Résultat attendu

- Catalogue fiable des portails PBIRS
- Détection des « shadow portals » non documentés
- Base de référence pour supervision et gouvernance des accès

---

## 12) Conclusion

La gouvernance PBIRS réussie repose sur une logique « produit + exploitation » :

- standardiser,
- sécuriser,
- **encadrer les rafraîchissements (sans limite native, cf. §6.7)**,
- monitorer,
- tester la résilience,
- clarifier les responsabilités.

Le principal différenciateur avec Power BI Service est simple : **en on-prem, vous maîtrisez davantage… mais vous opérez davantage**, et **vous êtes seul à fixer les garde-fous** que le cloud impose nativement.

---

## 13) Références officielles Microsoft

### Power BI Report Server (on-prem)

- [Admin overview — Power BI Report Server](https://learn.microsoft.com/en-us/power-bi/report-server/admin-handbook-overview)
- [System requirements](https://learn.microsoft.com/en-us/power-bi/report-server/system-requirements)
- [Install Power BI Report Server](https://learn.microsoft.com/en-us/power-bi/report-server/install-report-server)
- [Migrate a report server installation](https://learn.microsoft.com/en-us/power-bi/report-server/migrate-report-server)
- [Scheduled refresh in PBIRS — architecture & limites](https://learn.microsoft.com/en-us/power-bi/report-server/scheduled-refresh)
- [Configure scheduled refresh on a Power BI report (PBIRS)](https://learn.microsoft.com/en-us/power-bi/report-server/configure-scheduled-refresh)
- [Reporting Services Configuration Manager](https://learn.microsoft.com/en-us/sql/reporting-services/install-windows/reporting-services-configuration-manager-native-mode)
- [Reporting Services security and protection](https://learn.microsoft.com/en-us/sql/reporting-services/security/reporting-services-security-and-protection)
- [Monitor an Analysis Services instance](https://learn.microsoft.com/en-us/sql/analysis-services/instances/monitor-an-analysis-services-instance)
- [Memory Properties (SSAS)](https://learn.microsoft.com/en-us/sql/analysis-services/server-properties/memory-properties)

### Power BI Service / Fabric

- [Data refresh in Power BI](https://learn.microsoft.com/en-us/power-bi/connect-data/refresh-data)
- [Configure scheduled refresh (service)](https://learn.microsoft.com/en-us/power-bi/connect-data/refresh-scheduled-refresh)
- [Troubleshooting refresh scenarios](https://learn.microsoft.com/en-us/power-bi/connect-data/refresh-troubleshooting-refresh-scenarios)
- [What is an on-premises data gateway?](https://learn.microsoft.com/en-us/power-bi/connect-data/service-gateway-onprem)
- [Manage data sources — import and scheduled refresh](https://learn.microsoft.com/en-us/power-bi/connect-data/service-gateway-enterprise-manage-scheduled-refresh)
- [Incremental refresh overview](https://learn.microsoft.com/en-us/power-bi/connect-data/incremental-refresh-overview)
- [Aggregations in Power BI](https://learn.microsoft.com/en-us/power-bi/enterprise/aggregations-auto)
- [Power BI Premium — Capacities and SKUs](https://learn.microsoft.com/en-us/power-bi/enterprise/service-premium-what-is)
- [Workspace monitoring](https://learn.microsoft.com/en-us/fabric/fundamentals/workspace-monitoring-overview)
- [Row-level security (RLS)](https://learn.microsoft.com/en-us/fabric/security/service-admin-row-level-security)

### Adoption & gouvernance

- [Power BI implementation planning — Adoption roadmap](https://learn.microsoft.com/en-us/power-bi/guidance/powerbi-adoption-roadmap-overview)
- [Power BI implementation planning — Tenant administration](https://learn.microsoft.com/en-us/power-bi/guidance/powerbi-implementation-planning-tenant-administration-overview)
- [Power BI security baseline](https://learn.microsoft.com/en-us/power-bi/guidance/powerbi-implementation-planning-security-overview)
- [Power BI auditing & monitoring](https://learn.microsoft.com/en-us/power-bi/enterprise/service-admin-auditing)
- [Microsoft Purview — Data governance for Power BI](https://learn.microsoft.com/en-us/purview/how-to-enable-data-use-management-power-bi)

> Tous ces liens pointent vers la documentation Microsoft Learn officielle, maintenue à jour par Microsoft. En cas de doute sur une règle de gouvernance, c'est la référence à citer en priorité.
