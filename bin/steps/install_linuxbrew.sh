#!/usr/bin/env bash


if [ ! -x "$(which brew)" ]; then

    puts-step "Installing Linuxbrew"
    do-debug "Building linuxbrew in $HOME"
    echo -e 'y\n' | ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install)" |& indent |& brew_quiet

    git_commit_check

    puts-step "Installing GCC"
    brew install gcc |& indent |& brew_quiet

#    puts-step "Installing lz4"
#    brew install lz4 |& indent |& brew_quiet

else

    puts-step "Linuxbrew already installed"
    do-debug "\$(which brew)=$(which brew)"
    git_commit_check

fi

do-debug "brew config:"
brew config |& indent-debug || true

do-debug "brew doctor:"
brew doctor |& indent-debug || true
