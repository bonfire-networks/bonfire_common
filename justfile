# recipes for the `just` command runner: https://just.systems
# how to install: https://github.com/casey/just#packages

# the central source of truth for Bonfire extension project boilerplate
# is tracked at https://github.com/bonfire-networks/bonfire-extension-boilerplate

# we load all vars from .env file into the env of just commands
set dotenv-load
# and export just vars as env vars
set export

## Main configs - override these using env vars

APP_VSN_EXTRA := env_var_or_default("APP_VSN_EXTRA", "")
DB_DOCKER_VERSION := env_var_or_default('DB_DOCKER_VERSION', "17-3.5")
DB_DOCKER_IMAGE := env_var_or_default('DB_DOCKER_IMAGE', if arch() == "aarch64" { "ghcr.io/baosystems/postgis:"+DB_DOCKER_VERSION } else { "postgis/postgis:"+DB_DOCKER_VERSION+"-alpine" })
DB_STARTUP_TIME := env_var_or_default("DB_STARTUP_TIME", "10")
POSTGRES_PORT := env_var_or_default("POSTGRES_PORT", "5432")
MIX_ENV := env_var_or_default("MIX_ENV", "test")
POSTGRES_USER := env_var_or_default("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD := env_var_or_default("POSTGRES_PASSWORD", "postgres")
POSTGRES_DB := env_var_or_default("POSTGRES_DB", "localhost:" + POSTGRES_PORT)

## Configure just
# choose shell for running recipes
set shell := ["bash", "-uec"]
# support args like $1, $2, etc, and $@ for all args
set positional-arguments


#### COMMANDS ####

help:
    @echo "Just commands:"
    @just --list

compile:
    mix compile

clean: stop-test-db clean-symlinks
    mix deps.clean --all
    rm -rf .hex .mix .cache _build deps

clean-symlinks:
    find lib/ -type l -delete

boilerplate-update:
    mkdir -p .bonfire-extension-boilerplate
    git clone https://github.com/bonfire-networks/bonfire-extension-boilerplate.git --branch main --single-branch .bonfire-extension-boilerplate
    cd .bonfire-extension-boilerplate && cp .envrc justfile .gitignore .. && cp .github/workflows/main.yml ../.github/workflows/main.yml && cp lib/mix/mess.ex ../mess.exs
    rm -rf .bonfire-extension-boilerplate

deps-get:
    mix deps.get

deps-update:
    mix deps.update --all

common-mix-tasks-setup:
    cd lib/mix/ && ([ -d ../../deps/bonfire_common/lib/mix_tasks ] && ln -sf ../../deps/bonfire_common/lib/mix_tasks tasks || ln -sf ../mix_tasks tasks) && cd -
    cd lib/mix/tasks/release/ && MIX_ENV=prod mix escript.build && cd -

ext-migrations-copy: common-mix-tasks-setup
    mkdir -p priv/repo
    mix bonfire.extension.copy_migrations --to priv/repo/migrations --repo Bonfire.Common.Repo --force

run-tests *args:
    mix test {{args}}

test *args: start-test-db ext-migrations-copy create-test-db (run-tests args)

create-test-db:
    mix ecto.create -r Bonfire.Common.Repo

start-test-db:
    docker run --name test-db -d -p {{POSTGRES_PORT}}:5432 -e POSTGRES_USER=${POSTGRES_USER} -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} --rm ${DB_DOCKER_IMAGE}
    # Let the db start
    sleep {{DB_STARTUP_TIME}}

stop-test-db:
    docker rm -f test-db

@release-increment: common-mix-tasks-setup
    #!/usr/bin/env bash
    set -euxo pipefail
    export MIX_ENV="prod"
    lib/mix/tasks/release/release ./ {{APP_VSN_EXTRA}}

release: release-increment
   version="$(grep -E 'version: \"(.*)\",' mix.exs | sed -E 's/^.*version: \"(.*)\",$/\1/')"; git add mix.exs && git commit -m "Release v${version}" && git tag "v${version}"

push-release: release
    git push
    git push --tags