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

brew tap linuxbrew/extra |& indent || true

puts-step "Linuxbrew configuration:"
brew config |& indent || true

puts-step "Running 'brew doctor':"
brew doctor |& indent || true

# run even if already installed in case the first core-tools install was interrupted
# 21-MAY-2017 remove requirement to install core tools except gawk which is required for this buildpack to work right
brew_do install gawk
#brew_install_defaults
