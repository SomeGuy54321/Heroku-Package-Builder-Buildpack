#!/usr/bin/env bash


function run_user_script() {
    set +e
    SCRIPT="$1"
    puts-step "Running '"$(basename "$SCRIPT")"'"
    chmod +x "$SCRIPT" |& indent
    # the traced output is sent to stderr, |& redirects stderr to stdout
    bash -o xtrace "$SCRIPT" |& indent_notime | indent
    puts-step "Finished '"$(basename "$SCRIPT")"' with exit code $?"
    set -e
}

function package_manage() {
    local ACTION=${1/ /}
    local MAIN_VAR="PACKAGE_EXTRAS_"$ACTION"[@]"

    local REMAINING_PACKAGES

    for package in ${!MAIN_VAR}; do
        if [ $(time_remaining) -gt 60 ]; then
            # multiple options flags allowed so add [@]
            local OPTIONS_VAR="PACKAGE_EXTRAS_options_${package}[@]"
            local OPTIONS
            for opt in ${!OPTIONS_VAR}; do
                OPTIONS="$OPTIONS --${opt}"
            done

            # only one formula allowed
            # THIS PART MUST BE JUST BEFORE brew_do!
            local FORMULAS_VAR="PACKAGE_EXTRAS_formulas_${package}"
            local FORMULAS="${!FORMULAS_VAR}"
            local INFO
            if [ ${#FORMULAS} -eq 0 ]; then
                # if package name contains "-" the user should've replaced it with "__" in the yaml
                FORMULAS=${package/__/-}
                INFO=${FORMULAS}
            else
                INFO="${package/__/-} from $FORMULAS"
            fi

            # do the thing
            puts-step "$(proper_word ${ACTION})ing $INFO"
            brew_do ${ACTION} ${FORMULAS} ${OPTIONS}
            unset FORMULAS_VAR FORMULAS OPTIONS_VAR OPTIONS

            # multiple scripts can run
            local CONFIG_VAR="PACKAGE_EXTRAS_config_${package}[@]"
            for script in ${!CONFIG_VAR}; do
                run_user_script "$BUILD_DIR/$script"
                unset script
            done
        else
            REMAINING_PACKAGES="$package\n$REMAINING_PACKAGES"
        fi
    done

    if [ ${#REMAINING_PACKAGES} -gt 0 ]; then
        puts-warn "The following packages did not ${ACTION} in time:"
        echo -e $REMAINING_PACKAGES |& indent_notime | indent
        puts-warn "Try building again or increasing your PACKAGE_BUILDER_MAX_BUILDTIME configvar."
    fi
}

function main() {

    if [ ${USE_DPKG_BUILDFLAGS} -ne 0 ] && [ -x "$(which dpkg-buildflags)" ]; then
        do-debug "Exporting dpkg-buildflags:"
        dpkg-buildflags --status |& indent-debug || true
        eval $(dpkg-buildflags --export=sh)
    fi

    # the only thing this line does is displays the variables just for debugging, no variables are set
    do-debug "YAML variables:"
    parse_yaml $BUILD_DIR/package-extras.yaml 'PACKAGE_EXTRAS_' |& indent-debug

    puts-step "Parsing package-extras.yaml"
    eval $(parse_yaml $BUILD_DIR/package-extras.yaml 'PACKAGE_EXTRAS_')

    package_manage install
    package_manage reinstall
    package_manage uninstall

    # delete all but the latest downloads of installed packages, or older than 30 days
    puts-step "Running brew cleanup"
    brew cleanup |& indent |& brew_quiet
}

main
