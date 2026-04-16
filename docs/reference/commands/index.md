# Commands Reference

Reference for declarative commands defined in `devbox/commands/`.

## app

- [app.install](app/install.md) — Install the Laravel application via installer container

## db

- [db.create](db/create.md) *(private)* — Create a database in the db container
- [db.start](db/start.md) *(private)* — Start the database container and wait until healthy
- [db.up](db/up.md) *(private)* — Start the database container in the background
- [db.wait](db/wait.md) *(private)* — Wait for all containers to become healthy

## services.main

- [services.main.bootstrap](services/main/bootstrap.md) — Full bootstrap — start db, create database, install deps, generate key, run migrations
- [services.main.composer-install](services/main/composer-install.md) — Install PHP dependencies via Composer
- [services.main.key-generate](services/main/key-generate.md) — Generate the Laravel application key
- [services.main.migrate](services/main/migrate.md) — Run Laravel database migrations

## services.main.db

- [services.main.db.create](services/main/db/create.md) *(private)* — Create the main service database

## services.second

- [services.second.bootstrap](services/second/bootstrap.md) — Full bootstrap — start db, create database, install deps, generate key, run migrations
- [services.second.composer-install](services/second/composer-install.md) — Install PHP dependencies via Composer
- [services.second.key-generate](services/second/key-generate.md) — Generate the Laravel application key
- [services.second.migrate](services/second/migrate.md) — Run Laravel database migrations

## services.second.db

- [services.second.db.create](services/second/db/create.md) *(private)* — Create the second service database

