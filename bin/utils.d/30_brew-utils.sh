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

function brew_do() {
    set +e  # don't exit if error
    declare -l ACTION=${1/ /}
    local PACKAGE=$2
    local FLAGS=${@:3}
    if [ $(time_remaining) -gt 0 ]; then
        local JOB_REDUCE_MAX_TRIES=${4:-$JOB_REDUCE_MAX_TRIES}

        # install dependencies incrementally
        if [ ${ACTION} = "install" ]; then
            local DEPS=$(brew deps ${PACKAGE})
            if [ ${#DEPS} -gt 0 ]; then
                puts-step "Incrementally installing dependencies for ${PACKAGE}: $(echo -n ${DEPS} | sed 's/ /, /g')"
                for dep in ${DEPS}; do
                    IS_INSTALLED=$(brew_checkfor ${dep})
                    if [ $IS_INSTALLED -eq 0 ]; then
                        brew_do ${ACTION} ${dep}
                    else
                        puts-step "${dep} has already been installed by Linuxbrew"
                    fi
                done
            fi
        fi

        puts-step "Running 'brew $ACTION $PACKAGE $FLAGS'"
        brew ${ACTION} ${PACKAGE} ${FLAGS} |& brew_outputhandler

        # about brilliant PIPESTATUS: http://stackoverflow.com/a/1221870/4106215
        BREW_RTN_STATUS=${PIPESTATUS[0]}
        # brew_outputhandler will write "is_reinstall" to brew_test_results.txt if the
        # text 'Error: No such keg: ' appeared in the output
        local CHECK_ALREADY_INSTALLED=$(grep --count is_reinstall /tmp/brew_test_results.txt 2>/dev/null || echo 0)
        export INSTALL_TRY_NUMBER=$(( $INSTALL_TRY_NUMBER + 1 ))
        if [ ${CHECK_ALREADY_INSTALLED:-0} -eq 0 ] && [ ${BREW_RTN_STATUS} -ne 0 ]; then

            # if we haven't exhausted out job-reduce tries then decrement HOMEBREW_MAKE_JOBS and try again
            if [ ${INSTALL_TRY_NUMBER:-1} -le ${JOB_REDUCE_MAX_TRIES:-1} ]; then

                retry_print $PACKAGE $(max 1 $(( $HOMEBREW_MAKE_JOBS - $(job_reduce_increment) )))
                brew_do $ACTION $PACKAGE $FLAGS

            # if we're at our INSTALL_TRY_NUMBER and we're still not on single threading try that before giving up
            elif [ ${INSTALL_TRY_NUMBER:-1} -eq $(( ${JOB_REDUCE_MAX_TRIES:-1} + 1 )) ] && [ ${HOMEBREW_MAKE_JOBS:-1} -ne 1 ]; then

                retry_print $PACKAGE 1
                brew_do $ACTION $PACKAGE $FLAGS

            # else it's failed
            else
                if [ ${PACKAGE_BUILDER_NOBUILDFAIL:-0} -eq 0 ] && [ "$ACTION" != "uninstall" ]; then
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
    else
        puts-warn "Not enough time to install ${PACKAGE}"
    fi
    set -e
}

function brew_checkfor() {
    brew list | grep --count "$1"
}

function brew_install_defaults() {
    # install core tools
    if [ ${PACKAGE_BUILDER_NOINSTALL_DEFAULTS:-0} -ne 1 ]; then

        puts-step "Installing core tools"
#        local CHECK

        # gcc & glibc wont install without a newer gawk
        if [ ${PACKAGE_BUILDER_NOINSTALL_GAWK:-0} -ne 1 ]; then  # [ $(time_remaining) -gt 0 ] && [ $(brew_checkfor gawk) -eq 0 ]
            puts-step "Installing gawk"
            brew_do install gawk
        fi

        if [ ${PACKAGE_BUILDER_NOINSTALL_GCC:-0} -ne 1 ]; then  # [ $(time_remaining) -gt 0 ] && [ $(brew_checkfor gcc) -eq 0 ] &&
            puts-step "Installing GCC"
            brew_do install gcc '--with-glibc' # --with-java --with-jit --with-multilib --with-nls'
        fi

#        if [ $(time_remaining) -gt 0 ] && [ $(brew_checkfor ruby) -eq 0 ] && [ ${PACKAGE_BUILDER_NOINSTALL_RUBY:-0} -ne 1 ]; then
#            puts-step "Installing Ruby"
#            brew_do install ruby '--with-libffi'
#        fi
#
#        if [ $(time_remaining) -gt 0 ] && [ $(brew_checkfor perl) -eq 0 ] && [ ${PACKAGE_BUILDER_NOINSTALL_PERL:-0} -ne 1 ]; then
#            puts-step "Installing Perl"
#            brew_do install perl #'--without-test'
#        fi
#
#        if [ $(time_remaining) -gt 0 ] && [ $(brew_checkfor python3) -eq 0 ] && [ ${PACKAGE_BUILDER_NOINSTALL_PYTHON:-0} -ne 1 ]; then
#            puts-step "Installing Python3"
#            brew_do install python3 '--with-tcl-tk --with-quicktest'
#        fi
    fi
}

# makes the brew output not show lines starting with '  ==>'
function brew_quiet() {
    if [ ${PACKAGE_BUILDER_INSTALL_QUIET:-0} -gt 0 ]; then
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

# creating this (originally) so install_packages.sh doesn't keep trying to install
# a package that it can't find.
function brew_outputhandler() {
#    local TEST='{if ($0 ~ /Error: No such keg: /) { print "'"$Y"'" > "'"brew_test_results.txt"'"; print $0; } else { print $0; } }'
    local TEST='{ if ($0 ~ /Error: No such keg: / || $0 ~ /Error: No available formula with the name / || $0 ~ /Error: No formulae found in taps/) { print "is_reinstall" > "/tmp/brew_test_results.txt"; } print $0; system(""); }'
    awk "$TEST" | indent
}
