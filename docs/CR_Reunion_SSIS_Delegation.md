# Compte-Rendu — Problématique de Délégation SSIS

**Date :** 3 avril 2026  
**Participants :** Julien, Mathias, et autres  
**Sujet :** Problèmes de délégation avec SSIS et solutions de contournement

---

## 1. Problème de Délégation avec SSIS *(3:49)*

- **Constat :** SSIS **ne peut pas déléguer** sur un compte Active Directory en **délégation contrainte** (Kerberos Constrained Delegation).
- **Validation :** Mathias a confirmé ce comportement avec un **article officiel Microsoft** documentant cette limitation.

> ⚠️ Il s'agit d'une limitation connue de SSIS, pas d'un défaut de configuration.

---

## 2. Solution de Contournement avec SQL Agent *(4:40)*

- **Approche testée :** Utilisation de **SQL Server Agent** déployé sur le même serveur que SSIS pour orchestrer les packages.
- **Résultat :** Des **problèmes d'accès à plusieurs bases de données** ont été rencontrés avec cette approche.

---

## 3. Gestion des Tickets Kerberos *(6:18)*

- **Solution mise en place :** Gestion des tickets Kerberos **au niveau d'Airflow** pour permettre la délégation.
- **Mécanisme :** Utilisation de **groupes d'accès** pour autoriser le **double hop** (double saut d'authentification) vers les quais de données.

---

## 4. Problème d'Accès aux Bases de Données *(8:42)*

- **Constat :** Problèmes persistants d'accès aux bases de données avec SSIS.
- **Solution de contournement :** Utilisation d'un **compte SQL Server en authentification SQL Server** (au lieu de l'authentification Windows/AD).
- **Inconvénient :** Nécessite de **stocker et sécuriser les credentials** (mot de passe du compte SQL).

---

## 5. Problème Résiduel — Droits Traversants *(13:34)*

- **Constat :** SSIS nécessite des **droits traversants (traverse permissions)** sur **tous les répertoires** entre le niveau du partage réseau et le niveau d'accès final.
- **Impact :** Cette contrainte pose des **questions importantes lors de la migration** vers une nouvelle infrastructure de stockage (héritage des droits sur les partages).

---

## 6. Prochaines Étapes *(21:43)*

| Action | Responsable | Statut |
|--------|-------------|--------|
| Recueillir toutes les **versions** (SSIS, SQL Server, OS) et informations nécessaires | Participants → Julien | 🔲 À faire |
| **Partager** les informations collectées avec Julien | Participants | 🔲 À faire |
| **Ouvrir un case support Microsoft** pour clarifier la partie héritage des droits sur les partages | À définir | 🔲 À faire |

---

## Synthèse des Problèmes et Solutions

| Problème | Solution / Contournement | Statut |
|----------|--------------------------|--------|
| Délégation contrainte SSIS impossible | Limitation connue Microsoft — pas de fix | ❌ Bloquant |
| Accès multi-BDD via SQL Agent | SQL Agent sur même serveur | ⚠️ Partiel |
| Double hop Kerberos | Gestion tickets Kerberos via Airflow + groupes d'accès | ✅ En place |
| Accès BDD depuis SSIS | Compte SQL Server (auth SQL) | ⚠️ Contournement (credentials à sécuriser) |
| Droits traversants sur répertoires | Case support Microsoft à ouvrir | 🔲 En investigation |

---

*Document généré le 3 avril 2026 — À compléter avec les informations collectées par les participants.*
