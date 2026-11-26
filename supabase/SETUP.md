# Configuration Supabase — AfriReach

Ce guide concerne exclusivement le projet Supabase **AfriReach**. Ne jamais exécuter ces commandes dans une base AQUI NET HUB.

## 1. Créer le projet
- Nom : `afriareach`
- Région conseillée : `eu-west-1` (Europe, latence généralement adaptée à l'Afrique de l'Ouest).
- Utiliser un projet neuf, indépendant.
- Vérifier le coût affiché avant toute création. Ne pas confirmer un coût non nul sans accord explicite.

## 2. Installer le schéma
Dans le SQL Editor du projet AfriReach uniquement, exécuter le contenu de `schema.sql`.
Le schéma n'a pas encore été exécuté ni testé sur une base réelle : il doit être validé sur le projet neuf avant toute donnée réelle.

## 3. Créer le premier administrateur
1. Créer d'abord un compte utilisateur AfriReach avec l'écran d'inscription Supabase Auth.
2. Dans Authentication > Users, copier l'UUID de ce compte.
3. Dans le SQL Editor AfriReach, exécuter en remplaçant l'UUID :

```sql
insert into public.platform_admins (user_id)
values ('UUID_DU_COMPTE_ADMIN');
```

Ne jamais donner ce rôle depuis le navigateur ni depuis les métadonnées modifiables du profil.

## 4. Autoriser un compte annonceur
L'inscription publique crée uniquement les rôles `participant` ou `creator`. Après vérification manuelle d'un annonceur, un administrateur peut lui attribuer le rôle :

```sql
update public.profiles
set account_type = 'advertiser', updated_at = now()
where id = 'UUID_DU_COMPTE_ANNONCEUR';
```

## 5. Vérifications obligatoires avant lancement
- Tester les politiques RLS avec des comptes distincts (participant, créateur, annonceur, administrateur).
- Vérifier qu'un utilisateur ne peut ni modifier le propriétaire, ni le montant, ni le statut d'une campagne appartenant à autrui.
- Vérifier qu'un annonceur ne peut pas valider sa propre preuve de frais.
- Vérifier qu'un participant ne peut confirmer que son propre paiement.
- Configurer un stockage privé pour les justificatifs, avec des règles d'accès dédiées. Ne pas utiliser de liens publics pour les preuves.
- Ajouter les fonctions serveur nécessaires à la validation des campagnes et à la journalisation des décisions administrateur.
- Configurer les limites de taille/type des fichiers et une politique de conservation/suppression.
- Effectuer une revue juridique et réglementaire locale avant d'accepter des campagnes ou paiements commerciaux.

## Sécurité
- Le frontend ne doit contenir que l'URL du projet et sa clé publishable/anon.
- Ne jamais exposer `service_role`, une clé secrète, un mot de passe ou une clé privée dans Git, le navigateur ou une capture publique.
- Les transferts de récompenses sont directs entre annonceur et participant. AfriReach ne doit pas recevoir ni conserver l'argent des récompenses dans ce pilote.
- Les options Flooz, TMoney et bancaires restent inactives tant qu'elles ne sont pas officiellement configurées et autorisées.
