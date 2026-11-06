# TimeFix

Clone mobile de Google Calendar.

| Dossier | Contenu | État |
|---|---|---|
| [`flutter/`](flutter/README.md) | Application mobile Android / iOS (Flutter) : planning, semaine, mois ; calendriers locaux, iCal, Google et CalDAV | ✅ |
| [`backend/`](backend/README.md) | Serveur CalDAV auto-hébergé en C# (ASP.NET Core), Docker, PostgreSQL ou SQLite | ✅ |

Démarrage rapide du serveur :

```bash
cd backend
cp .env.example .env
docker compose up -d
```

Puis, dans l'application : **Ajouter un calendrier → Compte CalDAV**.

Voir [flutter/README.md](flutter/README.md) et [backend/README.md](backend/README.md).
