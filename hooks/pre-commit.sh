#!/bin/sh

STAGED_TS_FILES=$(git diff --staged --name-only | grep '\.ts$' | xargs)
STAGED_SOL_FILES=$(git diff --staged --name-only | grep '\.sol$' | xargs)


if [ -n "$STAGED_SOL_FILES" ]; then
    GENERATED_FILES=$(yarn --silent solidity-interfacer "$STAGED_SOL_FILES" --license 'GNU AGPLv3' --logFiles | xargs)

    if [ -n "$GENERATED_FILES" ]; then
        yarn prettier --config .prettierrc.json --write $GENERATED_FILES
        git add "$GENERATED_FILES"
    fi

    yarn prettier --config .prettierrc.json --write $STAGED_SOL_FILES
fi

if [ -n "$STAGED_TS_FILES" ]; then
    yarn prettier --config .prettierrc.json --write $STAGED_TS_FILES
fi
