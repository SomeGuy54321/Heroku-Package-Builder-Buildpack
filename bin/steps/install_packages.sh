#!/usr/bin/env bash


function run_user_script() {
    set +e
    SCRIPT="$1"
    puts-step "Running '"$(basename "$SCRIPT")"'"
    chmod +x "$SCRIPT" |& indent
    # the traced output is sent to stderr, |& redirects stderr to stdout
    bash -o xtrace "$SCRIPT" |& indent | indent
    puts-step "Finished '"$(basename "$SCRIPT")"' with exit code $?"
    set -e
}

function main() {

    # add a configvar to control this
    USE_DPKG_BUILDFLAGS=1
    if [ $USE_DPKG_BUILDFLAGS -neq 0 ]; then eval $(dpkg-buildflags --export); fi

    puts-step "Parsing package-extras.yaml"
    eval $(parse_yaml $BUILD_DIR/package-extras.yaml "PACKAGE_EXTRAS_")
    #do-debug "Parsed YAML variables:"
    #debug_heavy "PACKAGE_EXTRAS_"
    local REMAINING_PACKAGES
    local REMAINING_UPACKAGES
    for package in ${PACKAGE_EXTRAS_install[@]}; do

        if [ $(time_remaining) -gt 0 ]; then

            # only one formula allowed
            local FORMULAS_VAR="PACKAGE_EXTRAS_formulas_${package}"
            local FORMULAS="${!FORMULAS_VAR}"
            [ ${#FORMULAS} -eq 0 ] && FORMULAS=$package || true

            # multiple options flags allowed so add [@]
            local OPTIONS_VAR="PACKAGE_EXTRAS_options_${package}[@]"
            local OPTIONS
            for opt in ${!OPTIONS_VAR}; do
                OPTIONS="$OPTIONS --${opt}"
            done

            # do the thing
            puts-step "Installing $package"
            brew_do install $FORMULAS $OPTIONS

            # multiple scripts can run
            local CONFIG_VAR="PACKAGE_EXTRAS_config_${package}[@]"
            for script in ${!CONFIG_VAR}; do
                run_user_script "$BUILD_DIR/$script"
            done
        else
            REMAINING_PACKAGES="$REMAINING_PACKAGES\n- $package"
        fi
    done

    if [ ${#REMAINING_PACKAGES} -gt 0 ]; then
        puts-warn "The following packages did not install in time:"
        echo -e $REMAINING_PACKAGES |& indent | indent
        puts-warn "Try building again or increasing your PACKAGE_BUILDER_MAX_BUILDTIME configvar."
    fi

    # reinstall things
    for rpackage in ${PACKAGE_EXTRAS_reinstall[@]}; do
        if [ $(time_remaining) -gt 0 ]; then

            # only one formula allowed
            local RFORMULAS_VAR="PACKAGE_EXTRAS_formulas_${rpackage}"
            local RFORMULAS="${!RFORMULAS_VAR}"
            [ ${#RFORMULAS} -eq 0 ] && RFORMULAS=$rpackage || true

            puts-step "Reinstalling $rpackage"
            brew_do reinstall $RFORMULAS

        else
            REMAINING_RPACKAGES="$REMAINING_UPACKAGES\n- $rpackage"
        fi
    done

    if [ ${#REMAINING_RPACKAGES} -gt 0 ]; then
        puts-warn "The following packages did not reinstall in time:"
        echo -e $REMAINING_RPACKAGES |& indent | indent
        puts-warn "Try building again or increasing your PACKAGE_BUILDER_MAX_BUILDTIME configvar."
    fi

    # uninstall things
    for upackage in ${PACKAGE_EXTRAS_uninstall[@]}; do
        if [ $(time_remaining) -gt 0 ]; then

            # only one formula allowed
            local UFORMULAS_VAR="PACKAGE_EXTRAS_formulas_${upackage}"
            local UFORMULAS="${!UFORMULAS_VAR}"
            [ ${#UFORMULAS} -eq 0 ] && UFORMULAS=$upackage || true

            puts-step "Uninstalling $upackage"
            brew_do uninstall $UFORMULAS

        else
            REMAINING_UPACKAGES="$REMAINING_UPACKAGES\n- $upackage"
        fi
    done

    if [ ${#REMAINING_UPACKAGES} -gt 0 ]; then
        puts-warn "The following packages did not uninstall in time:"
        echo -e $REMAINING_UPACKAGES |& indent | indent
        puts-warn "Try building again or increasing your PACKAGE_BUILDER_MAX_BUILDTIME configvar."
    fi

    # delete all but the latest downloads of installed packages, or older than 30 days
    puts-step "Running brew cleanup"
    brew cleanup --prume=30 |& indent |& brew_quiet
}

main
