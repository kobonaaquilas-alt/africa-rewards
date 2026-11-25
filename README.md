# AfriReach

Plateforme en préparation mettant en relation annonceurs, créateurs et participants autour de campagnes publicitaires transparentes.

## État actuel
Cette première livraison est une **vitrine responsive installable (PWA)**. Elle ne crée pas encore de comptes, ne collecte pas de données, ne publie pas de campagnes et ne traite aucun paiement. Le formulaire de préinscription est volontairement non connecté.

## Principes produit
- Pas d'achat d'abonnés, de likes, de commentaires ou de vues artificiels.
- Pas de mission qui manipule les statistiques ou enfreint les règles des plateformes tierces.
- Paiements manuels uniquement dans le pilote, après validation des preuves.
- Les paiements entre annonceur et participant restent directs ; AfriReach ne conserve pas les fonds des participants.
- Les moyens Flooz, TMoney et bancaires restent affichés comme options futures inactives.

## Déploiement Cloudflare Pages
- Framework preset : None
- Build command : laisser vide
- Build output directory : /
- Root directory : /

Connecter ce dépôt à Cloudflare Pages. Pour une publication de fichiers statiques, aucune compilation n'est requise.

## Prochaines étapes techniques
1. Créer un projet Supabase distinct pour AfriReach.
2. Exécuter le script `supabase/schema.sql` dans le SQL Editor.
3. Configurer l'authentification, les rôles et les règles RLS.
4. Connecter le frontend à Supabase via les variables publiques du projet (URL et anon/publishable key uniquement).
5. Construire l'espace membre, les campagnes, les preuves de frais de service et le suivi des paiements directs.
6. Effectuer les vérifications de sécurité, de conformité et de fonctionnement avant toute campagne réelle.

Ne jamais placer la clé `service_role`, un secret ou un mot de passe dans le frontend ou dans Git.
