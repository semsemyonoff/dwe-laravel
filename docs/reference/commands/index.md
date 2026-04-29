# Commands Reference

Reference for declarative commands defined in `devbox/commands/`.

## app

- [app.install](app/install.md) — Install the Laravel application via installer container

## db

- [db.cli](db/cli.md) — Connect to the database in the db container
- [db.create](db/create.md) — Create a database in the db container
- [db.drop](db/drop.md) — Drop the database in the db container

## services.main

- [services.main.bootstrap](services/main/bootstrap.md) — Full bootstrap — start db, create database, install deps, generate key, run migrations
- [services.main.composer-install](services/main/composer-install.md) — Install PHP dependencies via Composer
- [services.main.key-generate](services/main/key-generate.md) — Generate the Laravel application key
- [services.main.migrate](services/main/migrate.md) — Run Laravel database migrations

## services.second

- [services.second.bootstrap](services/second/bootstrap.md) — Full bootstrap — start db, create database, install deps, generate key, run migrations
- [services.second.composer-install](services/second/composer-install.md) — Install PHP dependencies via Composer
- [services.second.key-generate](services/second/key-generate.md) — Generate the Laravel application key
- [services.second.migrate](services/second/migrate.md) — Run Laravel database migrations

