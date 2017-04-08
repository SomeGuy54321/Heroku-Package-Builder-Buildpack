#!/usr/bin/env bash


if [ ! -x "$(which brew)" ]; then

    puts-step "Installing Linuxbrew"
    do-debug "Building linuxbrew in $HOME"
    echo -e 'y\n' | ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install)" |& indent |& brew_quiet

    brew_install_defaults

    do-debug "brew config:"
    brew config |& indent-debug || true

    do-debug "brew doctor:"
    brew doctor |& indent-debug || true

else

    puts-step "Linuxbrew already installed"
    do-debug "\$(which brew)=$(which brew)"

    brew update-reset |& indent-debug || true

    do-debug "brew config:"
    brew config |& indent-debug || true

    do-debug "brew doctor:"
    brew doctor |& indent-debug || true

    #git_checks_linuxbrew
    git_rebuild_latest

    do-debug "brew config:"
    brew config |& indent-debug || true

fi
