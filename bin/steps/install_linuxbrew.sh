#!/usr/bin/env bash


if [ ! -x "$(which brew)" ]; then

    puts-step "Installing Linuxbrew"
    do-debug "Building linuxbrew in $HOME"
    echo -e 'y\n' | ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install)" |& brew_outputhandler

else

    puts-step "Linuxbrew already installed"
    do-debug "\$(which brew)=$(which brew)"

    puts-step "Restoring Linuxbrew"
    git_rebuild_latest

    puts-step "Cleaning Linuxbrew"
    do-debug "Running 'brew prune'"
    brew prune |& indent

fi

do-debug "brew config:"
brew config |& indent-debug || true

do-debug "brew doctor:"
brew doctor |& indent-debug || true

# run even if already installed in case the first core-tools install was interrupted
brew_install_defaults
