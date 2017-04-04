#!/usr/bin/env bash

# this can cause forking issues, if it does then
# gradually reduce the jobs number
export HOMEBREW_MAKE_JOBS=$(grep -c ^processor /proc/cpuinfo)

# if the install fails, assume it's cuz of a
# forking issue and reduce job numbers by this
# amount
JOB_REDUCE_INCREMENT=2

# if we try reducing the job number by JOB_REDUCE_INCREMENT
# JOB_REDUCE_TRIES number of times and it still failes then
# just reduce to 1 job immediately
JOB_REDUCE_MAX_TRIES=4

function retry_print() {
    PACKAGE="$1"
    NUM_JOBS=$2
    puts-warn "Installation of $PACKAGE failed using $HOMEBREW_MAKE_JOBS processor cores"
    export HOMEBREW_MAKE_JOBS=$NUM_JOBS
    puts-step "Retrying installation of $PACKAGE with $HOMEBREW_MAKE_JOBS cores" |& indent
}

function fail_print() {
    PACKAGE="$1"
    puts-warn "Unable to install $PACKAGE even at $HOMEBREW_MAKE_JOBS job(s)."
    echo "This build will now fail. Sorry about that.
Perhaps consider removing $PACKAGE from your brew-extras.yaml file and retrying.
If that doesn't work then remove this buildpack from your build and let the
current buildpack maintainer know. Copy-paste this buildlog into an email to
him/her." |& indent
}

function brew_do() {
    set +e  # don't exit if error

    ACTION=$1
    PACKAGE="$2"
    FLAGS="$3"
    export INSTALL_TRY_NUMBER=$(( $INSTALL_TRY_NUMBER + 1 ))

    brew $ACTION $PACKAGE $FLAGS |& indent |& brew_quiet

    # if the install failed try again
    if [ $? -gt 0 ]; then

        # if we haven't exhausted out job-reduce tries then decrement HOMEBREW_MAKE_JOBS and try again
        if [ $INSTALL_TRY_NUMBER -le $JOB_REDUCE_MAX_TRIES ]; then

            retry_print $PACKAGE $(max 1 $(( $HOMEBREW_MAKE_JOBS - $JOB_REDUCE_INCREMENT )))
            brew_do $ACTION $PACKAGE $FLAGS

        # if we're at our INSTALL_TRY_NUMBER and we're still not on single threading try that before giving up
        elif [ $INSTALL_TRY_NUMBER -eq $(( $JOB_REDUCE_MAX_TRIES + 1 )) ] && [ $HOMEBREW_MAKE_JOBS -neq 1 ]; then

            retry_print $PACKAGE 1
            brew_do $ACTION $PACKAGE $FLAGS

        # else it's failed
        else
            if [ $PACKAGE_BUILDER_NOBUILDFAIL -eq 0 ] && [[ "$ACTION" != "uninstall" ]]; then
                fail_print $PACKAGE
                exit $?
            else
                puts-warn "Unable to install ${PACKAGE}. Continuing since PACKAGE_BUILDER_NOBUILDFAIL > 0 or you're doing an uninstall."
            fi
        fi
    fi

    # reset to exiting if error
    set -e
}

function brew_install() {
    INSTALL_TRY_NUMBER=0
    PACKAGE="$1"
    FLAGS="$2"
    do-debug "Running 'brew install $PACKAGE $FLAGS'"
    brew_do install "$PACKAGE" "$FLAGS"
}

function brew_uninstall() {
    INSTALL_TRY_NUMBER=0
    PACKAGE="$1"
    FLAGS="$2"
    do-debug "Running 'brew uninstall $PACKAGE $FLAGS'"
    brew_do uninstall "$PACKAGE" "$FLAGS"
}

function run_user_script() {
    SCRIPT="$1"
    puts-step "Running '"$(basename "$SCRIPT")"'"
    chmod +x "$SCRIPT" |& indent
    # the traced output is sent to stderr, |& redirects stderr to stdout
    bash -o xtrace "$SCRIPT" |& indent | indent
    puts-step "Finished '"$(basename "$SCRIPT")"'"
}

function main() {

    puts-step "Parsing package-extras.yaml"
    eval $(parse_yaml $BUILD_DIR/package-extras.yaml "PACKAGE_EXTRAS_")
    #do-debug "Parsed YAML variables:"
    #debug_heavy "PACKAGE_EXTRAS_"
    for package in ${PACKAGE_EXTRAS_packages[@]}; do

        if [ $(time_remaining) -gt 0 ]; then

            # only one formula allowed
            FORMULAS_VAR="PACKAGE_EXTRAS_formulas_${package}"
            FORMULAS="${!FORMULAS_VAR}"
            [ ${#FORMULAS} -eq 0 ] && FORMULAS=$package || true

            # multiple options flags allowed so add [@]
            OPTIONS_VAR="PACKAGE_EXTRAS_options_${package}[@]"
            for opt in ${!OPTIONS_VAR}; do
                OPTIONS="$OPTIONS --${opt}"
            done

            # do the thing
            puts-step "Installing $package"
            brew_install $FORMULAS $OPTIONS

            # multiple scripts can run
            CONFIG_VAR="PACKAGE_EXTRAS_config_${package}[@]"
            for script in ${!CONFIG_VAR}; do
                run_user_script "$BUILD_DIR/$script"
            done
        else
            REMAINING_PACKAGES="$REMAINING_PACKAGES\n- $package"
        fi
    done

    if [ ${#REMAINING_PACKAGES} -gt 0 ]; then
        puts-warn "The following packages did not install in time:"
        echo -e $REMAINING_PACKAGES |& indent
        puts-warn "Try building again or increasing your PACKAGE_BUILDER_MAX_BUILDTIME configvar."
    fi

    # uninstall things
    for upackage in ${PACKAGE_EXTRAS_uninstall[@]}; do
        if [ $(time_remaining) -gt 0 ]; then
            brew_uninstall $upackage
        else
            REMAINING_UNINSTALLS="$REMAINING_UNINSTALLS\n- $upackage"
        fi
    done

    if [ ${#REMAINING_UNINSTALLS} -gt 0 ]; then
        puts-warn "The following packages did not uninstall in time:"
        echo -e $REMAINING_UNINSTALLS |& indent
        puts-warn "Try building again or increasing your PACKAGE_BUILDER_MAX_BUILDTIME configvar."
    fi

    puts-step "Running brew cleanup"
    brew cleanup |& indent |& brew_quiet
}

main
