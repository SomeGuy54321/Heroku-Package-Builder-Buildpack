#!/usr/bin/env bash

# if we try reducing the job number by JOB_REDUCE_INCREMENT
# JOB_REDUCE_TRIES number of times and it still failes then
# just reduce to 1 job immediately
JOB_REDUCE_MAX_TRIES=4

# this can cause forking issues, if it does then
# gradually reduce the jobs number
export HOMEBREW_MAKE_JOBS=$(grep --count ^processor /proc/cpuinfo)

function job_reduce_increment() {
    local MAX_TRIES=$1
    local MAX_JOBS=$(grep --count ^processor /proc/cpuinfo)
    if [ ${#MAX_TRIES} -eq 0 ]; then MAX_TRIES=$JOB_REDUCE_MAX_TRIES; fi
    max 1 $(( $MAX_JOBS / MAX_JOBS ))
}

function retry_print() {
    local PACKAGE="$1"
    local NUM_JOBS=$2
    puts-warn "Installation of $PACKAGE failed using $HOMEBREW_MAKE_JOBS processor cores"
    export HOMEBREW_MAKE_JOBS=$NUM_JOBS
    puts-step "Retrying installation of $PACKAGE with $HOMEBREW_MAKE_JOBS cores" |& indent
}

function fail_print() {
    local PACKAGE="$1"
    puts-warn "Unable to install $PACKAGE even at $HOMEBREW_MAKE_JOBS job(s)."
    echo "This build will now fail. Sorry about that.
Perhaps consider removing $PACKAGE from your brew-extras.yaml file and retrying.
If that doesn't work then remove this buildpack from your build and let the
current buildpack maintainer know. Copy-paste this buildlog into an email to
him/her." |& indent
}

function echo_default() {
    VAL="$1"
    DEF="$2"]
    if [ ${#VAL} -eq 0 ]; then echo "$DEF"; else echo "$VAL"; fi
}

function brew_do() {
    set +e  # don't exit if error

    local ACTION=$1
    local PACKAGE="$2"
    local FLAGS="$3"
    local JOB_REDUCE_MAX_TRIES=$(echo_default $4 $JOB_REDUCE_MAX_TRIES)

    export INSTALL_TRY_NUMBER=$(( $INSTALL_TRY_NUMBER + 1 ))

    do-debug "Running 'brew $ACTION $PACKAGE $FLAGS'"
    brew $ACTION $PACKAGE $FLAGS |& indent |& brew_quiet

    # if the install failed try again
    if [ $? -gt 0 ]; then

        # if we haven't exhausted out job-reduce tries then decrement HOMEBREW_MAKE_JOBS and try again
        if [ $INSTALL_TRY_NUMBER -le $JOB_REDUCE_MAX_TRIES ]; then

            retry_print $PACKAGE $(max 1 $(( $HOMEBREW_MAKE_JOBS - $(job_reduce_increment) )))
            brew_do $ACTION $PACKAGE $FLAGS

        # if we're at our INSTALL_TRY_NUMBER and we're still not on single threading try that before giving up
        elif [ $INSTALL_TRY_NUMBER -eq $(( $JOB_REDUCE_MAX_TRIES + 1 )) ] && [ $HOMEBREW_MAKE_JOBS -neq 1 ]; then

            retry_print $PACKAGE 1
            brew_do $ACTION $PACKAGE $FLAGS

        # else it's failed
        else
            if [ $PACKAGE_BUILDER_NOBUILDFAIL -eq 0 ] && [[ "$ACTION" != "uninstall" ]]; then
                fail_print $PACKAGE
                unset INSTALL_TRY_NUMBER
                exit $?
            else
                puts-warn "Unable to install ${PACKAGE}. Continuing since PACKAGE_BUILDER_NOBUILDFAIL > 0 or you're doing an uninstall."
            fi
        fi
    fi

    # reset to exiting if error
    unset INSTALL_TRY_NUMBER
    set -e
}

function brew_checkfor_tools() {
    local CHECKFOR="$1"
    local PATH_TO_CHECKFOR="$(which $CHECKFOR)"
    if [ ${#PATH_TO_CHECKFOR} -eq 0 ]; then echo 0; fi
    CHECK=${PATH_TO_CHECKFOR/.linuxbrew/}
    if [ ${#PATH_TO_CHECKFOR} -gt ${#CHECK} ]; then echo 1; fi
}

function brew_install_defaults() {
    # install core tools
    if [ $PACKAGE_BUILDER_NOINSTALL_DEFAULTS -neq 1 ]; then

        brew_checkfor_tools gcc
        if [ $(time_remaining) -gt 0 ] && [ $? -eq 1 ] && [ $PACKAGE_BUILDER_NOINSTALL_GCC -neq 1 ]; then
            puts-step "Installing GCC"
            brew_do install gcc
        fi

        brew_checkfor_tools ruby
        if [ $(time_remaining) -gt 0 ] && [ $? -eq 1 ] && [ $PACKAGE_BUILDER_NOINSTALL_RUBY -neq 1 ]; then
            puts-step "Installing Ruby"
            brew_do install ruby
        fi

        brew_checkfor_tools perl
        if [ $(time_remaining) -gt 0 ] && [ $? -eq 1 ] && [ $PACKAGE_BUILDER_NOINSTALL_PERL -neq 1 ]; then
            puts-step "Installing Perl"
            brew_do install perl
        fi

        brew_checkfor_tools python3
        if [ $(time_remaining) -gt 0 ] && [ $? -eq 1 ] && [ $PACKAGE_BUILDER_NOINSTALL_PYTHON -neq 1 ]; then
            puts-step "Installing Python3"
            brew_do install python3
        fi
    fi
}

# makes the brew output not show lines starting with '  ==>'
function brew_quiet() {
    if [ $PACKAGE_BUILDER_INSTALL_QUIET -gt 0 ]; then
        grep -vE --line-buffered '^\s*==>'
    else
        tee
    fi
}


function show_linuxbrew() {
    do-debug "Contents of $HOME/.linuxbrew:"
    ls -Flah $HOME/.linuxbrew | indent-debug || true
    do-debug "Contents of $HOME/.linuxbrew/bin:"
    ls -Flah $HOME/.linuxbrew/bin | indent-debug || true
    do-debug "Contents of $HOME/.linuxbrew/Cellar:"
    ls -Flah $HOME/.linuxbrew/Cellar | indent-debug || true
}

function show_linuxbrew_files() {
    show_files $BUILD_DIR/.cache
    show_files $BUILD_DIR/.linuxbrew
    show_files $APP_DIR/.cache
    show_files $APP_DIR/.linuxbrew
    show_files $CACHE_DIR/.cache
    show_files $CACHE_DIR/.linuxbrew
    show_linuxbrew
}

