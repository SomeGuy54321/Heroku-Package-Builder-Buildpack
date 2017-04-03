#!/usr/bin/env bash

DEBUG_HERE=1

# defaults:
# HOMEBREW_PREFIX: /app/.linuxbrew
# HOMEBREW_REPOSITORY: /app/.linuxbrew
# HOMEBREW_CELLAR: /app/.linuxbrew/Cellar


if [ ! -x "$(which brew)" ]; then
    puts-step "Installing Linuxbrew"
    do-debug "Building linuxbrew in $HOME"

    echo -e 'y\n' | ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install)" |& indent |& brew_quiet

    puts-step "Aggressively optimizing git repo"
    git --git-repo="$BUILD_DIR/.linuxbrew/.git" gc --aggressive

    puts-step "Installing GCC"
    brew install gcc |& indent |& brew_quiet

else

    puts-step "Linuxbrew already installed"
    do-debug "which brew = $(which brew)"

    puts-step "Auto-optimizing git repo"
    git --git-repo="$BUILD_DIR/.linuxbrew/.git" gc --auto

    puts-step "Updating Linuxbrew"
    brew update |& indent |& brew_quiet

fi
