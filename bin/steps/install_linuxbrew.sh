#!/usr/bin/env bash

DEBUG_HERE=1

# linuxbrew bases its installation on the HOME variable
# so TEMPORARILY we set this to the BUILD_DIR
OLD_HOME=$HOME
export HOME=$BUILD_DIR

if [ ! -x "$(which brew)" ]; then
    debug_heavy
    puts-step "Installing Linuxbrew"
    do-debug "Building linuxbrew in $HOME"

    echo -r 'y\n' | ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install)" | indent
    OLD_PATH=$PATH
    export PATH="$HOME/.linuxbrew/bin:$PATH"

    # defaults:
    # HOMEBREW_PREFIX: /app/.linuxbrew
    # HOMEBREW_REPOSITORY: /app/.linuxbrew
    # HOMEBREW_CELLAR: /app/.linuxbrew/Cellar
    #ORIGINAL_HOMEBREW_PREFIX=$HOMEBREW_PREFIX
    #ORIGINAL_HOMEBREW_REPOSITORY=$HOMEBREW_REPOSITORY
    #ORIGINAL_HOMEBREW_CELLAR=$HOMEBREW_CELLAR

    ## set to builddir
    #export HOMEBREW_PREFIX=""
    #export HOMEBREW_REPOSITORY=""
    #export HOMEBREW_CELLAR=""

    puts-step "Installing GCC"
    brew install gcc | indent
    debug_heavy
else
    puts-step "Linuxbrew already installed"
    do-debug "which brew = $(which brew)"
fi


# install selected packages
debug_heavy
source $BIN_DIR/steps/install_packages.sh


# reset to default locations
export HOME=$OLD_HOME
do-debug "HOME reset to $HOME"
export PATH=$OLD_PATH
do-debug "PATH reset to $PATH"

#export HOMEBREW_PREFIX=""
#export HOMEBREW_REPOSITORY=""
#export HOMEBREW_CELLAR=""
