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

function max() {
    python -c "print(max($1,$2))"
}

function retry-print() {
    PACKAGE="$1"
    NUM_JOBS=$2
    puts-warn "Installation of $PACKAGE failed using $HOMEBREW_MAKE_JOBS processor cores"
    export HOMEBREW_MAKE_JOBS=$NUM_JOBS
    echo "Retrying installation of $PACKAGE with $HOMEBREW_MAKE_JOBS cores" | indent
}

function fail-print() {
    PACKAGE="$1"
    puts-warn "Unable to install $PACKAGE even at $HOMEBREW_MAKE_JOBS job(s)."
    echo -e "This build will now fail. Sorry about that.\n
Perhaps consider removing $PACKAGE from your brew-extras.yaml file and retrying.\n
If that doesn't work then remove this buildpack from your build and let the\n
current buildpack maintainer know. Copy-paste this buildlog into an email to\n
him/her." | indent
}

INSTALL_TRY_NUMBER=0
function brew-install() {
    set +e  # don't exit if error

    PACKAGE="$1"
    FLAGS="$2"
    export INSTALL_TRY_NUMBER=$(( $INSTALL_TRY_NUMBER + 1 ))

    brew install $PACKAGE $FLAGS

    # if the install failed try again
    if [ $? -gt 0 ]; then

        # if we haven't exhausted out job-reduce tries then decrement HOMEBREW_MAKE_JOBS and try again
        if [ $INSTALL_TRY_NUMBER -le $JOB_REDUCE_MAX_TRIES ]; then

            retry-print $PACKAGE $(max 1 $(( $HOMEBREW_MAKE_JOBS - $JOB_REDUCE_INCREMENT )))
            brew-install $PACKAGE

        # if we're at our INSTALL_TRY_NUMBER and we're still not on single threading try that
        # before giving up
        elif [ $INSTALL_TRY_NUMBER -eq $(( $JOB_REDUCE_MAX_TRIES + 1 )) ] && [ $HOMEBREW_MAKE_JOBS -neq 1 ]; then

            retry-print $PACKAGE 1
            brew-install $PACKAGE

        # else it's failed
        else
            fail-print
            exit $?
        fi
    fi

    reset to exiting if error
    set -e
}

function main() {
    eval $(parse-yaml $HOME/package-extras.yaml "PACKAGE_EXTRAS_")
    for package in ${PACKAGE_EXTRAS_packages[@]}; do

        # only one formula allowed
        FORMULAS_VAR="PACKAGE_EXTRAS_formulas_${package}"
        FORMULAS="${!FORMULAS_VAR}"
        if [ ${#FORMULAS} -eq 0 ]; then
            FORMULAS=$package;
        fi

        # multiple options flags allowed so add [@]
        OPTIONS_VAR="PACKAGE_EXTRAS_options_${package}[@]"
        for opt in ${!OPTIONS_VAR}; do
            OPTIONS="$OPTIONS --${opt}"
        done

        # do the thing
        puts-step "Installing $package"
        brew-install $FORMULAS $OPTIONS

        # multiple scripts can run
        CONFIG_VAR="PACKAGE_EXTRAS_config_${package}[@]"
        for script in ${!CONFIG_VAR}; do
            chmod +x $TMP_APP_DIR/$script
            $TMP_APP_DIR/$script $@
        done
    done
}

main
