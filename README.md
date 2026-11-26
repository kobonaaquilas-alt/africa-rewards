# AfriReach

AfriReach est une plateforme indépendante qui met en relation annonceurs, créateurs et participants autour de campagnes transparentes.

## État actuel
- Vitrine responsive et installable (PWA).
- Inscription et connexion Supabase, consentement légal et vérification d'âge minimum 18 ans.
- Pages provisoires de conditions d'utilisation et confidentialité.
- Espaces participant/créateur et annonceur.
- Création de campagnes en brouillon, calcul serveur des frais de service.
- Candidatures, preuves privées des missions et des transferts, confirmation ou contestation des paiements directs.
- Espace de modération administrateur, paramètres de paiement et journal d'audit.
- Base Supabase indépendante, avec RLS et stockage privé.

Les paiements de frais à AfriReach ne sont pas encore ouverts : le premier administrateur doit configurer les coordonnées officielles de réception. Les campagnes ne peuvent donc pas être activées en production à ce stade.

## Principes
- Aucun achat artificiel d'abonnés, de likes, de commentaires ou de vues.
- Aucune mission qui manipule les statistiques ou enfreint les conditions des plateformes tierces.
- Frais de service pilote : 10 % du budget participants, minimum 100 XOF, calculés côté base.
- Récompenses transférées directement de l'annonceur au participant ; AfriReach ne conserve pas les fonds des récompenses.
- Flooz, TMoney et paiements bancaires restent inactifs.

## Déploiement Cloudflare Pages
- Framework preset : None
- Build command : laisser vide
- Build output directory : /
- Root directory : /

Connecter ce dépôt à Cloudflare Pages. Aucune compilation n'est nécessaire.

## Configuration
Lire supabase/SETUP.md pour le domaine Auth, le premier administrateur, les rôles, les règles financières et les vérifications de sécurité.

Ne jamais placer une clé service_role, un secret ou un mot de passe dans le frontend ou dans Git.
