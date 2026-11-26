# Configuration et exploitation — AfriReach

Ce guide concerne exclusivement le projet Supabase AfriReach (jdzseeodhdzbqvvubtnw). Ne jamais exécuter ces commandes dans une base AQUI NET HUB.

## État de la base
Le projet Supabase AfriReach est créé dans la région eu-west-1. Le schéma est appliqué et vérifié :
- 7 tables métier, avec RLS activé.
- Création automatique du profil après inscription.
- Rôles publics limités à participant et creator ; rôle annonceur attribué après vérification.
- Bucket privé afriareach-proofs pour les preuves (5 Mo max, JPEG/PNG/WEBP/PDF).
- Protections des transitions de campagnes, candidatures et paiements.
- Journal d'audit des changements administrateur.
- Contrôle de sécurité Supabase : aucune anomalie signalée.
- Les index encore « inutilisés » sont normaux sur une base neuve sans trafic.

## Configuration frontend
Le site utilise uniquement :
- URL : https://jdzseeodhdzbqvvubtnw.supabase.co
- Clé publishable : sb_publishable_Rl-SRvW-5gH5T61xuGLg1w_lwD6qRxd

Cette clé publishable est conçue pour être utilisée dans le navigateur. Aucune clé service_role ou clé secrète ne doit être ajoutée au frontend ou à Git.

## Première ouverture du compte administrateur
1. Publier le site AfriReach et définir son URL officielle.
2. Dans Supabase > Authentication > URL Configuration, définir cette URL comme Site URL et l'ajouter aux Redirect URLs.
3. Créer un compte AfriReach via l'écran « Mon espace » (un compte participant ou créateur).
4. Dans Supabase > Authentication > Users, copier l'UUID du compte.
5. Dans le SQL Editor du projet AfriReach uniquement, exécuter :

    insert into public.platform_admins (user_id)
    values ('UUID_DU_COMPTE_ADMIN');

Le rôle admin n'est jamais attribué depuis le navigateur ni depuis les métadonnées modifiables du profil.

## Attribution du rôle annonceur
Après vérification de l'entreprise ou du porteur de campagne, l'administrateur peut attribuer le rôle :

    update public.profiles
    set account_type = 'advertiser', updated_at = now()
    where id = 'UUID_DU_COMPTE_ANNONCEUR';

## Règles financières du pilote
- Frais de service AfriReach : 10 % du budget des récompenses, avec un minimum de 100 XOF, calculés côté base de données.
- Les frais de service sont payés à AfriReach et vérifiés par l'administration avant toute activation.
- Les récompenses sont transférées directement par l'annonceur au participant ; AfriReach ne conserve pas ces fonds.
- Les coordonnées de réception des frais AfriReach ne sont pas encore configurées. Aucun paiement de frais ne doit être demandé tant que les coordonnées officielles ne sont pas ajoutées.
- Flooz, TMoney, cartes et banques restent inactifs.

## Contrôles avant lancement commercial
- Tester avec plusieurs comptes indépendants (participant, créateur, annonceur et admin).
- Tester l'inscription et la confirmation e-mail sur le domaine réellement publié.
- Tester les permissions RLS, l'upload privé, la lecture des preuves par les parties autorisées et les transitions d'état.
- Ajouter les coordonnées officielles de paiement des frais de service et le support.
- Définir les conditions d'utilisation, la politique de confidentialité, la modération et les procédures de litige.
- Vérifier les obligations réglementaires et fiscales applicables localement avant d'accepter des campagnes réelles.
