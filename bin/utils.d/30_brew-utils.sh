#!/usr/bin/env bash

# if we try reducing the job number by JOB_REDUCE_INCREMENT
# JOB_REDUCE_TRIES number of times and it still failes then
# just reduce to 1 job immediately
JOB_REDUCE_MAX_TRIES=4

# this can cause forking issues, if it does then
# gradually reduce the jobs number
MAX_JOBS=$(grep --count ^processor /proc/cpuinfo || echo 1)
export HOMEBREW_MAKE_JOBS=${MAX_JOBS}


function job_reduce_increment() {
    local MAX_TRIES=${1:-$JOB_REDUCE_MAX_TRIES}
    local MAX_JOBS=$(grep --count ^processor /proc/cpuinfo || echo 1)
    max 1 $(( $MAX_JOBS / MAX_JOBS ))
}


function brew_reducejobs() {
    declare -i NEWJOBS=${1:-$(( $HOMEBREW_MAKE_JOBS - $(job_reduce_increment) ))}
    NEWJOBS=$(max 1 ${NEWJOBS})
    export HOMEBREW_MAKE_JOBS=${NEWJOBS}
}


function fail_print() {
    local ACTION=$1
    local PACKAGE=$2
    puts-warn "Unable to ${ACTION} $PACKAGE at $HOMEBREW_MAKE_JOBS job(s)."
    nullify_md5hashfile
    echo "This build will now fail. Sorry about that.
Perhaps consider removing $PACKAGE from your brew-extras.yaml, or changing
some of its 'options' parameters, or setting PACKAGE_BUILDER_BUILDFAIL=0 and
retrying. If that doesn't work then remove this buildpack from your build
and let the current buildpack maintainer know by copy-pasting this buildlog
into a Gitlab/Github issue, or sending an email to him/her." |& indent
}


function brew_do() {

    local PACKAGE=${2/ /}
    declare -l ACTION=${1/ /}
    local FLAGS=${@:3}
    local SKIP_DEPENDENCY_CHECK=${4:-0}

    if [ $(time_remaining) -gt 0 ]; then

        ## start checking if ACTION=='install' and the package is already installed
        if [ ${ACTION} == "install" ] && [ $(brew_checkfor ${PACKAGE}) -gt 0 ]; then  # check if package is already installed
                puts-step "${PACKAGE} has already been installed by Linuxbrew"

        # else its not installed and we should manage how it installs
        else
#            ## start checking for dependencies
#            if [ ${ACTION} = "install" ] || [ ${ACTION} = "reinstall" ]; then  # && [ ${SKIP_DEPENDENCY_CHECK} -ne 0 ]; then
#
#                local DEPS_INSTALLED=$(echo -n "$(brew deps --include-build ${PACKAGE} --installed)" | tr '\n' '|')
#                local DEPS=$(brew deps -n --include-optional --skip-recommended ${PACKAGE} | grep -vE "$DEPS_INSTALLED")
#
#                ## start installing dependencies recursively
#                # test Bash recursion with this:
#                # f() { declare -i X=${1:-0}; while [ $X -lt 6 ]; do X=$((X+1)); echo "${FUNCNAME[*]} $X"; f $X; done; }
#                if [ ${#DEPS} -gt 0 ]; then
#                    puts-step "Recursively installing dependencies for ${PACKAGE}: $(echo -n ${DEPS} | sed -u 's/ /, /g')"
#                    for dep in ${DEPS}; do
#                        IS_INSTALLED=$(brew_checkfor ${dep})
#                        if [ ${IS_INSTALLED} -eq 0 ]; then
#                            brew_do ${ACTION} ${dep}
#                        else
#                            puts-step "${dep} has already been installed by Linuxbrew"
#                        fi
#                    done
#                fi
#                ## end installing dependencies recursively
#            fi
#            ## end checking for dependencies

            # this is ugly but the time needs to be checked again since the incremental dependency install loop may have taken awhile
            ## start checking if theres time left for actual $ACTION
            if [ $(time_remaining) -gt 0 ]; then

                ## start no error block
                (set +e
                    ####################################################################################################
                    ## This is the most important part of the Linuxbrew part of the buildpack. Step-by-step:
                    # TODO: document the hard part of brew_do
                    # 1.)
                    puts-step "Running 'brew $ACTION $PACKAGE $FLAGS'"

                    # 2.)
                    proc_watcher 1 brew ${ACTION} ${PACKAGE} ${FLAGS} |& brew_outputhandler

                    # 3.)
                    #jobs -x proc_watcher %+
                    #declare -i BREW_PID=$(jobs -p | tail -n1)

                    # 4.)
                    #proc_watcher ${BREW_PID}

                    # 5.)
                    local BREW_RTN_STATUS=$?
                    do-debug "Received from proc_watcher BREW_RTN_STATUS is '$BREW_RTN_STATUS'"
                    ####################################################################################################


                    ## These variables should use the variable of the same name from the next highest scope,
                    # or automatically set INSTALL_TRY_NUMBER=0 if we're in the top scope.
                    # Test Bash scoping with this:
                    # f() { local X=$((X+1)); echo $X; (local X=$((X+1)); echo $X; (local X=$((X+1)); echo $X; echo $X;); echo $X;); echo $X; }

                    ## INSTALL_TRY_NUMBER: This is a global variable to track how many loops we've done with $PACKAGE
                    declare -i INSTALL_TRY_NUMBER=${INSTALL_TRY_NUMBER:-0}
                    do-debug "INSTALL_TRY_NUMBER is '$INSTALL_TRY_NUMBER'"

                    ## JOB_REDUCE_TRIES: This variable tracks how many times we've tried the job reduce errorhandling strategy
                    # Corresponds to 'syserrfail2in_error' in the errorfile
                    declare -i JOB_REDUCE_TRIES=${JOB_REDUCE_TRIES:-0}
                    do-debug "JOB_REDUCE_TRIES is '$JOB_REDUCE_TRIES'"

                    ## FILE_EXISTS_RETRIES: This variable tracks how many times we've delt with the 'Error: File exists ' error
                    declare -i FILE_EXISTS_RETRIES=${FILE_EXISTS_RETRIES:-0}
                    do-debug "FILE_EXISTS_RETRIES is '$FILE_EXISTS_RETRIES'"

                    ## SYSERRFAIL2IN_RETRIES: This variable tracks how many times we've delt with the 'syserr_fail2_in' error
                    declare -i SYSERRFAIL2IN_RETRIES=${SYSERRFAIL2IN_RETRIES:-0}
                    do-debug "SYSERRFAIL2IN_RETRIES is '$SYSERRFAIL2IN_RETRIES'"


                    ## brew_outputhandler will write one of the following to /tmp/brew_test_results.txt:
                    # "nonexistent_package_error"
                    # "fileexists_error"
                    # "syserrfail2in_error"
                    # "already_installed"
                    local CHECKERR_NONEXISTENT_PACKAGE=$(brew_checkerror nonexistent_package_error)
                    do-debug "CHECKERR_NONEXISTENT_PACKAGE is '$CHECKERR_NONEXISTENT_PACKAGE'"

                    local CHECKERR_FILEEXISTS=$(brew_checkerror fileexists_error)
                    do-debug "CHECKERR_FILEEXISTS is '$CHECKERR_FILEEXISTS'"

                    local CHECKERR_SYSERRFAIL2IN=$(brew_checkerror syserrfail2in_error)
                    do-debug "CHECKERR_SYSERRFAIL2IN is '$CHECKERR_SYSERRFAIL2IN'"

                    local CHECKERR_ISINSTALLED=$(brew_checkerror already_installed)
                    do-debug "CHECKERR_ISINSTALLED is '$CHECKERR_ISINSTALLED'"

                    do-debug "Clearing errorfile"
                    brew_clearerrorfile


                    ## start brew errorhandling
                    # check if the error was from the package not existing
                    if [ ${BREW_RTN_STATUS} -gt 0 ] && \
                       [ ${CHECKERR_NONEXISTENT_PACKAGE} -eq 0 ] && \
                       [ ${CHECKERR_ISINSTALLED} -eq 0 ] && \
                       [ $(time_remaining) -gt 0 ];
                    then
                        INSTALL_TRY_NUMBER=$(( INSTALL_TRY_NUMBER + 1 ))
                        puts-warn "$(proper_word ${ACTION})ation of ${PACKAGE} failed. Trying some things to fix it."

                        ## start handling of 'Error: File exists '
                        if [ ${CHECKERR_FILEEXISTS} -gt 0 ]; then

                            ## start handling of 'Error: File exists @ syserr_fail2_in'
                            if [ ${CHECKERR_SYSERRFAIL2IN} -gt 0 ] && [ ${SYSERRFAIL2IN_RETRIES} -lt 2 ]; then
                                SYSERRFAIL2IN_RETRIES=$(( SYSERRFAIL2IN_RETRIES + 1 ))

                                # SYSERRFAIL2IN_RETRIES will first enter ==0, then by the time it gets here it's ==1
                                case ${SYSERRFAIL2IN_RETRIES} in
                                1)
                                    puts-warn "Got the weird ruby error 'syserr_fail2_in'. Jumping to uninstall ${PACKAGE}."
                                    do-debug "Running 'brew uninstall ${PACKAGE}'"
                                    brew uninstall ${PACKAGE} |& indent_debug
                                    puts-step "Retrying ${ACTION}ation of $PACKAGE"
                                    brew_do $ACTION $PACKAGE $FLAGS
                                ;;
                                2)
                                    puts-warn "Still got the weird ruby error 'syserr_fail2_in'. Forcefully uninstalling ${PACKAGE}."
                                    do-debug "Running 'brew uninstall --force --ignore-dependencies ${PACKAGE}'"
                                    brew uninstall --force --ignore-dependencies ${PACKAGE} |& indent_debug
                                    puts-step "Retrying ${ACTION}ation of $PACKAGE"
                                    brew_do $ACTION $PACKAGE $FLAGS
                                ;;
                                esac
                            ## end handling of 'Error: File exists @ syserr_fail2_in'

                            ## if it's a 'Error: File exists ' error and not a 'Error: File exists @ syserr_fail2_in', or
                            # if we've done all we can for the 'Error: File exists @ syserr_fail2_in' error we get here
                            else
                                FILE_EXISTS_RETRIES=$(( FILE_EXISTS_RETRIES + 1 ))
                                case ${FILE_EXISTS_RETRIES} in
                                1)
                                    puts-warn "Got a weird ruby error. Running a possible remedy."
                                    do-debug    "This remedy was built when I had a failed gcc build, which was"
                                    # align these echos with do-debug text by indenting to the width of 'DEBUG: ' (+7)
                                    echo "       then archived, then upon decompressing and trying to restart  " |& indent_debug
                                    echo "       the build I'd get 'Error: File exists @ syserr_fail2_in'      " |& indent_debug
                                    do-debug "Running 'brew link --overwrite --force ${PACKAGE}'"
                                    brew link --overwrite --force ${PACKAGE} |& indent_debug
                                    puts-step "Retrying ${ACTION}ation of $PACKAGE"
                                    brew_do $ACTION $PACKAGE $FLAGS
                                ;;
                                2)
                                    puts-warn "Got another weird ruby error. Running another possible remedy."
                                    do-debug "Running 'brew cleanup -s ${PACKAGE}'"
                                    brew cleanup -s ${PACKAGE} |& indent_debug
                                    puts-step "Retrying ${ACTION}ation of $PACKAGE"
                                    brew_do $ACTION $PACKAGE $FLAGS
                                ;;
                                3)
                                    puts-warn "Yet another weird ruby error. Resorting to more drastic measures."
                                    do-debug "Running 'brew uninstall ${PACKAGE}'"
                                    brew uninstall ${PACKAGE} |& indent_debug
                                    puts-step "Retrying ${ACTION}ation of $PACKAGE"
                                    brew_do $ACTION $PACKAGE $FLAGS
                                ;;
                                *)
                                    puts-warn "Weird ruby error again. Last ditch effort to fix this."
                                    do-debug "Running 'brew uninstall --force --ignore-dependencies ${PACKAGE}'"
                                    brew uninstall --force --ignore-dependencies ${PACKAGE} |& indent_debug
                                    puts-step "Retrying ${ACTION}ation of $PACKAGE"
                                    brew_do $ACTION $PACKAGE $FLAGS
                                ;;
                                esac
                            fi
                            ## end handling of 'Error: File exists ' and 'Error: File exists @ syserr_fail2_in'
                        ## end handling of 'Error: File exists '

                        ## start seeing if the package actually exists and if the ACTION failed for some reason
                        else
                            JOB_REDUCE_TRIES=$(( JOB_REDUCE_TRIES + 1 ))

                            ## start checking that we haven't exhausted our job_reduce tries
                            case ${JOB_REDUCE_TRIES} in
                                [0-$(( JOB_REDUCE_MAX_TRIES - 1 ))])
                                    brew_reducejobs
                                    puts-step "Retrying ${ACTION}ation of $PACKAGE with $HOMEBREW_MAKE_JOBS cores"
                                    brew_do $ACTION $PACKAGE $FLAGS
                                ;;
                                ${JOB_REDUCE_MAX_TRIES})
                                    brew_reducejobs 1
                                    puts-step "Retrying ${ACTION}ation of $PACKAGE with $HOMEBREW_MAKE_JOBS cores"
                                    brew_do $ACTION $PACKAGE $FLAGS
                                ;;
                                *)
                                    # it's failed and we dont care
                                    if [ ${PACKAGE_BUILDER_BUILDFAIL:-0} -gt 0 ] && [ "$ACTION" != "uninstall" ]; then
                                        fail_print ${ACTION} ${PACKAGE}
                                        set -e
                                        exit ${BREW_RTN_STATUS}
                                    # else it's failed and we care
                                    else
                                        puts-warn "Unable to ${ACTION} ${PACKAGE}. Continuing since PACKAGE_BUILDER_BUILDFAIL==0 or you're doing an uninstall."
                                        nullify_md5hashfile
                                    fi
                                ;;
                            esac
                            ## end checking that we haven't exhausted our job_reduce tries
                        fi
                        ## end seeing if the package actually exists and if the ACTION failed for some reason
                    # we're at 'else' because brew_wait didnt return any error signals
                    else
                        ## start confirming $ACTION was successful
                        if [ $((CHECKERR_NONEXISTENT_PACKAGE + CHECKERR_ISINSTALLED)) -eq 0 ]; then

                            ## start see if we exited with an error
                            if [ ${BREW_RTN_STATUS} -eq 0 ]; then

                                ## start displaying different things depending on $ACTION
                                if [ "${ACTION}" == "install" ] || [ "${ACTION}" == "reinstall" ]; then

                                    ## start check the new $PACKAGE is available if doing re/install
                                    if [ $(brew_checkfor ${PACKAGE}) -gt 0 ]; then
                                        puts-step "Successfully ${ACTION}ed ${PACKAGE}"
                                    else
                                        puts-warn "Unsuccessful ${ACTION}ation of ${PACKAGE}..."
                                        nullify_md5hashfile
                                    fi
                                    ## end check the new $PACKAGE is available if doing re/install

                                elif [ "${ACTION}" == "uninstall" ]; then

                                    ## start check the new $PACKAGE is *not* available if doing uninstall
                                    if [ $(brew_checkfor ${PACKAGE}) -eq 0 ]; then
                                        puts-step "Successfully ${ACTION}ed ${PACKAGE}"
                                    else
                                        puts-warn "Unsuccessful ${ACTION}ation of ${PACKAGE}..."
                                        nullify_md5hashfile
                                    fi
                                    ## end check the new $PACKAGE is *not* available if doing uninstall

                                fi
                                ## end displaying different things depending on $ACTION

                            else
                                puts-warn "Leaving the ${ACTION} with an error code. You may need to log in to your app to see if everything worked out."
                                nullify_md5hashfile
                            fi
                            ## end see if we exited with an error
                        fi
                        ## end confirming $ACTION was successful
                    fi
                    ## end brew errorhandling
                )
                ## end no error block
            # ran out of time
            else
                puts-warn "Not enough time to ${ACTION} ${PACKAGE}"
                nullify_md5hashfile
            fi
            ## end checking if theres time left for actual $ACTION
        fi
        ## end checking if ACTION=='install' and the package is already installed
    else
        puts-warn "Not enough time to ${ACTION} ${PACKAGE}"
        nullify_md5hashfile
    fi
    export HOMEBREW_MAKE_JOBS=${MAX_JOBS}  # maybe the number of jobs wont be an issue for the next package.
}

function brew_checkfor() {
    local PACKAGE=${1}
    PACKAGE=$(basename "${PACKAGE}" | cut -d. -f1) # this needed in case a url is passed
    brew list | grep --count "$PACKAGE" || true
}

function brew_install_defaults() {
    # install core tools
    if [ ${PACKAGE_BUILDER_NOINSTALL_DEFAULTS:-0} -ne 1 ]; then

        puts-step "Installing core tools"

        # gcc & glibc wont install without a newer gawk
        # also this buildpack depends on having a newer gawk
        if [ ${PACKAGE_BUILDER_NOINSTALL_GAWK:-0} -ne 1 ] && [ $(brew_checkfor gawk) -eq 0 ]; then
            puts-step "Installing gawk"
            # these dont show up as dependencies but they are
            brew_do install patchelf
            brew_do install pkg-config
            brew_do install xz
            brew_do install gawk
        fi

        # user can still install gcc by specifying it in their package-extras.yaml file
        #if [ $(can_use_system_gcc) -eq 0 ]; then
            if [ ${PACKAGE_BUILDER_NOINSTALL_GCC:-0} -ne 1 ] && [ $(brew_checkfor gcc) -eq 0 ]; then
                puts-step "Installing GCC"
                # these dont show up as dependencies but they are
                brew_do install binutils
                brew_do install linux-headers
                brew_do install glibc
                brew_do install gcc
            fi
        #else
        #    export HOMEBREW_CC=gcc
        #fi

        ## These are disabled for now, they take a while to install
        if [ ${PACKAGE_BUILDER_NOINSTALL_RUBY:-1} -ne 1 ] && [ $(brew_checkfor ruby) -eq 0 ]; then
            puts-step "Installing Ruby"
            brew_do install ruby --with-libffi
        fi

        if [ ${PACKAGE_BUILDER_NOINSTALL_PERL:-1} -ne 1 ] && [ $(brew_checkfor perl) -eq 0 ]; then
            puts-step "Installing Perl"
            brew_do install perl --without-test
        fi

        if [ ${PACKAGE_BUILDER_NOINSTALL_PYTHON:-1} -ne 1 ] && [ $(brew_checkfor python3) -eq 0 ]; then
            puts-step "Installing Python3"
            brew_do install python3 --with-tcl-tk --with-quicktest
        fi
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
    ls -Flah $HOME/.linuxbrew | indent_debug || true
    do-debug "Contents of $HOME/.linuxbrew/bin:"
    ls -Flah $HOME/.linuxbrew/bin | indent_debug || true
    do-debug "Contents of $HOME/.linuxbrew/Cellar:"
    ls -Flah $HOME/.linuxbrew/Cellar | indent_debug || true
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
    # local ERRORFILE="${1:-/tmp/brew_test_results.txt}"
    local TEST='
    {
        if($0 ~ /Error: No such keg: /) {
            print "nonexistent_package_error" >> "/tmp/brew_test_results.txt";
        }
        if($0 ~ /Error: No available formula with the name /) {
            print "nonexistent_package_error" >> "/tmp/brew_test_results.txt";
        }
        if($0 ~ /Error: No formulae found in taps/) {
            print "nonexistent_package_error" >> "/tmp/brew_test_results.txt";
        }
        if($0 ~ /Warning: .+ already installed/) {
            print "already_installed" >> "/tmp/brew_test_results.txt";
        }
        if($0 ~ /syserr_fail2_in/) {
            print "syserrfail2in_error" >> "/tmp/brew_test_results.txt";
        }
        if($0 ~ /Error: File exists /) {
            print "fileexists_error" >> "/tmp/brew_test_results.txt";
        }
        print $0;
        system("");
    }'
    awk "$TEST" | indent
    return ${PIPESTATUS[0]}
}


function brew_checkerror() {
    CHECKFOR="$1"
    ERRORFILE="${2:-/tmp/brew_test_results.txt}"

    ## This is usually called from $() which pipes stderr to stdout, meaning
    # all errors must be suppressed.
    ## Short options for this command are '-Zsqc'
    grep --null                                  \
         --no-messages                           \
         --quiet                                 \
         --count "${CHECKFOR}" "${ERRORFILE}"    \
    &>/dev/null                               && \
    echo -n 1                                 || \
    echo -n 0;
    return 0
    # grep -Zsqc "${CHECKFOR}" "${ERRORFILE}" && echo -n 1 || echo -n 0
}


function brew_clearerrorfile() {
    ERRORFILE="${1:-/tmp/brew_test_results.txt}"
    rm -f "${ERRORFILE}" &>/dev/null || true
    touch "${ERRORFILE}" &>/dev/null || true
}

# According to this: https://github.com/Linuxbrew/legacy-linuxbrew/issues/415#issuecomment-105616862
# We can avoid installing gcc if gcc is version 4+, which saves 250 mb
function can_use_system_gcc() {
    local GCC_PATH=$(which gcc) #$(find_system_exe gcc)
    local MIN_GCC_VERSION=4.0
    local INSTALLED_GCC_VERSION=$(${GCC_PATH} -dumpversion)
    awk "BEGIN {if($INSTALLED_GCC_VERSION >= $MIN_GCC_VERSION) {printf(1);} else {printf(0);}}"
}

# According to this we can avoid installing glibc if gcc is version 2.19+, which saves ~250 mb
# https://github.com/Linuxbrew/legacy-linuxbrew/issues/813#issuecomment-184475893
# This says we can know the version with ldd:
# http://www.linuxquestions.org/questions/linux-software-2/how-to-check-glibc-version-263103/#post3842423
function can_use_system_glibc() {
    local LDD_PATH=$(which ldd) #$(find_system_exe ldd)
    local MIN_GLIBC_VERSION=2.19
    local INSTALLED_GLIBC_VERSION=$(${LDD_PATH} --version | head -n1 | rev | cut -d' ' -f1 | rev 2>/dev/null)
    awk "BEGIN {if($INSTALLED_GLIBC_VERSION >= $MIN_GLIBC_VERSION) {printf(1);} else {printf(0);}}"
}

function search_path() {
    local SEARCH_WORD="${1}"
    local OLDIFS=${IFS}
    IFS=':'
    local PATH_ARR="${PATH[@]}"
    for DIR in $PATH_ARR; do
        local MATCH_FILES=$(ls -1pAd --color=never ${DIR}/* 2>/dev/null | grep -v '/$' | grep --color=never -E "$SEARCH_WORD")
        if [ "$MATCH_FILES" != "" ]; then echo ${MATCH_FILES}; fi
    done
    local IFS=${OLDIFS}
}

## search everywhere in PATH except in .linuxbrew for an exe matching the version we want
#function find_system_gcc() {
#    local MIN_VERSION=${1:-4}
#    local EXE='[^0-9A-Za-z]gcc$'
#    local VERSION_COMMAND='-dumpversion'
#    local EXCLUDE_PATHSTR='.linuxbrew'
#    local OLDIFS=$IFS
#    export IFS="
#"
#    declare -a VERPATH
#    for exepath in $(search_path ${EXE} | grep -v '/$' | grep -Fv "$EXCLUDE_PATHSTR"); do
#        VERPATH+=($(${exepath} $VERSION_COMMAND 2>/dev/null)@${exepath})
#    done
#    export IFS=${OLDIFS}
#    local HIGHEST_VERSION=$(echo ${VERPATH[@]} | tr ' ' '\n' | sort -gr | cut -d'@' -f1 | head -n1)
#    if [ $(awk "BEGIN {if($MIN_VERSION > ${HIGHEST_VERSION:-0}) {printf(0);} else {printf(1);}}") -gt 0 ]; then
#        # try to get the highest version installed thats closest to root
#        declare -a HIGH_VERSION_EXES
#        for verexepath in $(echo ${VERPATH[*]} | tr ' ' '\n' | grep -F "${HIGHEST_VERSION}"); do
#            local exepath=$(echo ${verexepath} | cut -d'@' -f2); local exepath_len=${#exepath}
#            local exepath_noslashes=${exepath//\//}; local exepath_noslashes_len=${#exepath_noslashes}
#            local exepath_numslashes=$((exepath_len - exepath_noslashes_len))
#            HIGH_VERSION_EXES+=(${exepath_numslashes}@${exepath})
#        done
#        echo ${HIGH_VERSION_EXES[*]} | sort -g | head -n1 | cut -d'@' -f2
#    fi
#}
#
## search everywhere in PATH except in .linuxbrew for an exe matching the version we want
#function find_system_glibc() {
#    local MIN_VERSION=${1:-2.19}
#    local EXE='[^0-9A-Za-z]ldd$'
#    local VERSION_COMMAND='--version'
#    local EXCLUDE_PATHSTR='.linuxbrew'
#    local OLDIFS=$IFS
#    export IFS="
#"
#    declare -a VERPATH
#    for exepath in $(search_path ${EXE} | grep -v '/$' | grep -v "$EXCLUDE_PATHSTR"); do
#        VERPATH+=($(${exepath} $VERSION_COMMAND | head -n1 | rev | cut -d' ' -f1 | rev 2>/dev/null)@${exepath})
#        echo -n "${VERPATH[*]}"
#    done
#    export IFS=${OLDIFS}
#    local HIGHEST_VERSION=$(echo ${VERPATH[@]} | tr ' ' '\n' | sort -gr | cut -d'@' -f1 | head -n1)
#    if [ $(awk "BEGIN {if($MIN_VERSION > ${HIGHEST_VERSION:-0}) {printf(0);} else {printf(1);}}") -gt 0 ]; then
#        # try to get the highest version installed thats closest to root
#        declare -a HIGH_VERSION_EXES
#        for verexepath in $(echo ${VERPATH[*]} | tr ' ' '\n' | grep -F "${HIGHEST_VERSION}"); do
#            local exepath=$(echo ${verexepath} | cut -d'@' -f2); local exepath_len=${#exepath}
#            local exepath_noslashes=${exepath//\//}; local exepath_noslashes_len=${#exepath_noslashes}
#            local exepath_numslashes=$((exepath_len - exepath_noslashes_len))
#            HIGH_VERSION_EXES+=(${exepath_numslashes}@${exepath})
#        done
#        echo ${HIGH_VERSION_EXES[*]} | sort -g | head -n1 | cut -d'@' -f2
#    fi
#}
