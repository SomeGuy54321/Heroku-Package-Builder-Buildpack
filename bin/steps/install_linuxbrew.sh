#!/usr/bin/env bash

DEBUG_HERE=1

# defaults:
# HOMEBREW_PREFIX: /app/.linuxbrew
# HOMEBREW_REPOSITORY: /app/.linuxbrew
# HOMEBREW_CELLAR: /app/.linuxbrew/Cellar

# linuxbrew bases its installation on the HOME variable
# so TEMPORARILY we set this to the BUILD_DIR
OLD_HOME=$HOME
export HOME=$TMP_APP_DIR
OLD_PATH=$PATH
export PATH="$HOME/.linuxbrew/bin:$PATH"
do-debug "PATH before checking if we install linuxbrew: '$PATH'"

show_files
show_linuxbrew

if [ ! -x "$(which brew)" ]; then
    puts-step "Installing Linuxbrew"
    do-debug "Building linuxbrew in $HOME"

    echo -e 'y\n' | ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install)" | indent

    puts-step "Installing GCC"
    brew install gcc | indent #| brew_quiet
else
    puts-step "Linuxbrew already installed"
    do-debug "which brew = $(which brew)"
    puts-step "Updating Linuxbrew"
    brew update | indent #| brew_quiet
fi

# reset to default locations
export HOME=$OLD_HOME
do-debug "HOME reset to '$HOME'"
export PATH=$OLD_PATH
do-debug "PATH reset to '$PATH'"
