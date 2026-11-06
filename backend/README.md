# TimeFix — serveur CalDAV auto-hébergé (C#)

Serveur CalDAV écrit en C# (ASP.NET Core, .NET 10), déployé avec Docker, avec
PostgreSQL ou SQLite au choix. Il stocke les calendriers des utilisateurs de
l'application TimeFix, qui s'y connecte comme à n'importe quel serveur CalDAV.

## Démarrage rapide (Docker)

### Avec PostgreSQL (recommandé à plusieurs utilisateurs)

```bash
cd backend
cp .env.example .env    # puis changer les mots de passe
docker compose up -d
```

### Avec SQLite (un seul conteneur, idéal pour un usage personnel)

```bash
cd backend
cp .env.example .env    # POSTGRES_PASSWORD est alors inutile
docker compose -f docker-compose.sqlite.yml up -d
```

Au premier démarrage, le compte administrateur défini par
`TIMEFIX_ADMIN_USERNAME` / `TIMEFIX_ADMIN_PASSWORD` est créé avec un calendrier
« Personnel ». Le serveur écoute sur le port `TIMEFIX_PORT` (8080 par défaut).

Dans l'application : **Ajouter un calendrier → Compte CalDAV**, avec l'adresse
du serveur, l'identifiant et le mot de passe.

## HTTPS

L'authentification est en HTTP Basic, comme pour tous les serveurs CalDAV : le
serveur **doit** être exposé en HTTPS derrière un reverse proxy. Exemple avec
Caddy, qui obtient le certificat automatiquement :

```
cal.exemple.fr {
    reverse_proxy localhost:8080
}
```

Mettre alors `TIMEFIX_BEHIND_PROXY=true` (pour que la limitation de débit et le
blocage anti-force brute utilisent la vraie adresse du client) et ne plus
exposer le port 8080 publiquement. Pour servir sous un sous-chemin
(`https://exemple.fr/agenda`), définir `PathBase=/agenda`.

## Gestion des comptes

Il n'y a pas d'inscription publique : l'administrateur crée les comptes avec
l'API d'administration. Chaque nouveau compte reçoit un calendrier « Personnel ».

```bash
# Créer un utilisateur
curl -u admin:MOT_DE_PASSE_ADMIN -H 'Content-Type: application/json' -d '{"username":"marie","password":"un-mot-de-passe"}' https://cal.exemple.fr/api/admin/users
```

```bash
# Lister les utilisateurs
curl -u admin:MOT_DE_PASSE_ADMIN https://cal.exemple.fr/api/admin/users
```

```bash
# Réinitialiser un mot de passe
curl -u admin:MOT_DE_PASSE_ADMIN -X PUT -H 'Content-Type: application/json' -d '{"password":"nouveau-mot-de-passe"}' https://cal.exemple.fr/api/admin/users/marie/password
```

```bash
# Supprimer un utilisateur (et ses calendriers)
curl -u admin:MOT_DE_PASSE_ADMIN -X DELETE https://cal.exemple.fr/api/admin/users/marie
```

| Méthode | Route | Accès | Rôle |
|---|---|---|---|
| `GET` | `/api/me` | utilisateur | Infos du compte et URL CalDAV |
| `PUT` | `/api/me/password` | utilisateur | Changer son mot de passe (`currentPassword`, `newPassword`) |
| `GET` | `/api/admin/users` | admin | Lister les comptes |
| `POST` | `/api/admin/users` | admin | Créer un compte (`username`, `password`, `isAdmin`) |
| `PUT` | `/api/admin/users/{username}/password` | admin | Réinitialiser un mot de passe |
| `DELETE` | `/api/admin/users/{username}` | admin | Supprimer un compte (pas le dernier admin) |

Règles : identifiant de 2 à 32 caractères (`a-z`, `0-9`, `.`, `_`, `-`),
mot de passe d'au moins 8 caractères. Après 10 échecs d'authentification en
5 minutes, l'adresse IP est bloquée temporairement.

## Configuration

Variables d'environnement (`__` sépare les niveaux) :

| Variable | Défaut | Description |
|---|---|---|
| `Database__Provider` | `Sqlite` | `Sqlite` ou `Postgres` |
| `Database__ConnectionString` | `Data Source=/data/timefix.db` | Chaîne de connexion |
| `Admin__Username` / `Admin__Password` | — | Premier administrateur, créé si la base est vide |
| `DefaultCalendarName` | `Personnel` | Nom du calendrier créé pour chaque compte |
| `ReverseProxy__Enabled` | `false` | Faire confiance à `X-Forwarded-For` / `X-Forwarded-Proto` |
| `PathBase` | — | Préfixe d'URL si servi sous un sous-chemin |
| `CalDav__MaxResourceSize` | `1000000` | Taille maximale d'un événement (octets) |
| `RateLimit__PermitsPerMinute` | `600` | Requêtes par minute et par adresse IP |

Les migrations de la base sont appliquées automatiquement au démarrage.

## Protocole

| URL | Ressource |
|---|---|
| `/.well-known/caldav` | Redirection vers `/dav/` (découverte, RFC 6764) |
| `/dav/principals/{user}/` | Principal (`calendar-home-set`) |
| `/dav/calendars/{user}/` | Liste des calendriers |
| `/dav/calendars/{user}/{calendrier}/` | Calendrier (un `GET` exporte un seul fichier `.ics`) |
| `/dav/calendars/{user}/{calendrier}/{nom}.ics` | Événement |

Méthodes supportées : `OPTIONS`, `PROPFIND`, `PROPPATCH` (nom, description,
couleur), `MKCALENDAR`, `REPORT` (`calendar-query` avec filtre de composant et
de plage de dates, `calendar-multiget`), `GET`/`HEAD`, `PUT`, `DELETE`, avec
ETags et préconditions `If-Match` / `If-None-Match`. Propriétés courantes :
`current-user-principal`, `getctag`, `calendar-color` (Apple),
`supported-calendar-component-set`, `current-user-privilege-set`…

Limites de cette version :

* Compatibilité testée avec l'application TimeFix uniquement.
* Pas de `sync-collection` (synchro incrémentale) : les clients utilisent le `getctag`.
* Pas de partage de calendriers entre utilisateurs, d'invitations (CalDAV
  scheduling) ni de rappels côté serveur.
* Le filtre par plage de dates est volontairement large (marge de ±14 h pour
  les fuseaux horaires, séries sans fin considérées comme illimitées) : il peut
  renvoyer quelques événements en trop, jamais en moins.

## Développement

```bash
cd backend
dotnet run --project src/TimeFix.Server          # SQLite local, admin / admin-dev-password
dotnet test                                       # tests sur SQLite
```

```bash
# Mêmes tests sur PostgreSQL (une base temporaire par classe de tests)
TIMEFIX_TEST_POSTGRES="Host=localhost;Username=postgres;Password=…" dotnet test
```

Les migrations EF Core existent pour chaque fournisseur. Après une modification
du modèle :

```bash
dotnet tool install --global dotnet-ef
cd src/TimeFix.Server
dotnet ef migrations add NomDeLaMigration --context SqliteTimeFixDbContext --output-dir Data/Migrations/Sqlite
dotnet ef migrations add NomDeLaMigration --context PostgresTimeFixDbContext --output-dir Data/Migrations/Postgres
```

Organisation du code :

```
src/TimeFix.Server/
├── CalDav/      protocole : routeur (CalDavHandler), XML WebDAV, chemins, analyse iCalendar
├── Auth/        authentification Basic (cache des vérifications, blocage anti-force brute)
├── Users/       comptes (création, mots de passe, admin initial)
├── Api/         API JSON d'administration
├── Data/        Entity Framework Core (SQLite / PostgreSQL) et migrations
└── Program.cs   configuration, limitation de débit, routes, healthcheck Docker
```
