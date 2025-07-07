#!/bin/bash

cd /var/www/buyouts-frontend || exit
OLD_COMMIT=$(git rev-parse HEAD)
git pull origin master
NEW_COMMIT=$(git rev-parse HEAD)

if [ "$OLD_COMMIT" != "$NEW_COMMIT" ]; then
  npm install
  npm run build
fi
