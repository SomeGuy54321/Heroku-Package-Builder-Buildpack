#!/usr/bin/env bash

DEBUG_HERE=1

# defaults:
# HOMEBREW_PREFIX: /app/.linuxbrew
# HOMEBREW_REPOSITORY: /app/.linuxbrew
# HOMEBREW_CELLAR: /app/.linuxbrew/Cellar

# linuxbrew bases its installation on the HOME variable
# so TEMPORARILY we set this to the BUILD_DIR
OLD_HOME=$HOME
export HOME=$BUILD_DIR
OLD_PATH=$PATH
export PATH="$HOME/.linuxbrew/bin:$PATH"
OLD_MANPATH=$MANPATH
export MANPATH="$HOME/.linuxbrew/share/man:\$MANPATH"
OLD_INFOPATH=$INFOPATH
export INFOPATH="$HOME/.linuxbrew/share/info:\$INFOPATH"

if [ ! -x "$(which brew)" ]; then
    #debug_heavy
    puts-step "Installing Linuxbrew"
    do-debug "Building linuxbrew in $HOME"

    echo -e 'y\n' | ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install)" | indent

    puts-step "Installing GCC"
    brew install gcc | indent
    #debug_heavy

else
    puts-step "Linuxbrew already installed"
    do-debug "which brew = $(which brew)"
    puts-step "Updating Linuxbrew"
    brew update | indent
fi

if [ $BUILD_DEBUG -gt 0 ]; then export HOMEBREW_VERBOSE=1; fi
# install selected packages
#debug_heavy
source $BIN_DIR/steps/install_packages.sh


# reset to default locations
export HOME=$OLD_HOME
do-debug "HOME reset to '$HOME'"
export PATH=$OLD_PATH
do-debug "PATH reset to '$PATH'"
export MANPATH=$OLD_MANPATH
do-debug "MANPATH reset to '$MANPATH'"
export INFOPATH=$OLD_INFOPATH
do-debug "INFOPATH reset to '$INFOPATH'"
