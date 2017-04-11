#!/usr/bin/env bash

# if we try reducing the job number by JOB_REDUCE_INCREMENT
# JOB_REDUCE_TRIES number of times and it still failes then
# just reduce to 1 job immediately
JOB_REDUCE_MAX_TRIES=4

# this can cause forking issues, if it does then
# gradually reduce the jobs number
export HOMEBREW_MAKE_JOBS=$(grep --count ^processor /proc/cpuinfo || echo 1)

function job_reduce_increment() {
    local MAX_TRIES=${1:-$JOB_REDUCE_MAX_TRIES}
    local MAX_JOBS=$(grep --count ^processor /proc/cpuinfo || echo 1)
    max 1 $(( $MAX_JOBS / MAX_JOBS ))
}

function retry_print() {
    local ACTION=$1
    local PACKAGE="$2"
    local NUM_JOBS=$3
    puts-warn "$(proper_word ${ACTION})ation of ${PACKAGE} failed using $HOMEBREW_MAKE_JOBS processor cores"
    export HOMEBREW_MAKE_JOBS=${NUM_JOBS}
    puts-step "Retrying ${ACTION}ation of $PACKAGE with $HOMEBREW_MAKE_JOBS cores"
}

function fail_print() {
    local ACTION=$1
    local PACKAGE=$2
    puts-warn "Unable to ${ACTION} $PACKAGE even at $HOMEBREW_MAKE_JOBS job(s)."
    echo "This build will now fail. Sorry about that.
Perhaps consider removing $PACKAGE from your brew-extras.yaml file and retrying.
If that doesn't work then remove this buildpack from your build and let the
current buildpack maintainer know. Copy-paste this buildlog into an email to
him/her." |& indent
}

function brew_do() {

    local PACKAGE=${2/ /}
    declare -l ACTION=${1/ /}
    local FLAGS=${@:3}
    if [ $(time_remaining) -gt 0 ]; then
        if [ ${ACTION} == "install" ] && [ $(brew_checkfor ${PACKAGE}) -gt 0 ]; then  # check if package is already installed
                puts-step "${PACKAGE} has already been installed by Linuxbrew"
        else
            local INSTALL_TRY_NUMBER=${INSTALL_TRY_NUMBER:-0}  # takes the INSTALL_TRY_NUMBER from the next highest scope

            # install dependencies incrementally
            if [ ${ACTION} = "install" ] || [ ${ACTION} = "reinstall" ]; then
                local DEPS_INSTALLED=$(echo -n "$(brew deps --include-build ${PACKAGE} --installed)" | tr '\n' '|')
                local DEPS=$(brew deps -n --include-optional --skip-recommended ${PACKAGE} | grep -vE "$DEPS_INSTALLED")
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

            # this is ugly but the time needs to be checked again since the incremental dependency install loop may
            # have taken awhile...
            if [ $(time_remaining) -gt 0 ]; then

                # start no error block
                local BREW_RTN_STATUS
                (set +e
                puts-step "Running 'brew $ACTION $PACKAGE $FLAGS'"
                brew ${ACTION} ${PACKAGE} ${FLAGS} |& brew_outputhandler &
                declare -i BREW_PID=$(jobs -p | tail -n1)
                brew_watch ${BREW_PID}
                BREW_RTN_STATUS=$?
                )

                INSTALL_TRY_NUMBER=$(( $INSTALL_TRY_NUMBER + 1 ))
                ## brew_outputhandler will write one of the following to /tmp/brew_test_results.txt:
                # "nonexistent_package"
                # "clean_and_retry"
                local CHECK_NONEXISTENT_PACKAGE=$(grep -Zsqc nonexistent_package "/tmp/brew_test_results.txt" && echo -n 1 || echo -n 0)
                local CHECK_CLEAN_RETRY=$(grep -Zsqc clean_and_retry "/tmp/brew_test_results.txt" && echo -n 1 || echo -n 0)

                do-debug "BREW_RTN_STATUS=$BREW_RTN_STATUS"
                do-debug "CHECK_NONEXISTENT_PACKAGE=$CHECK_NONEXISTENT_PACKAGE"
                do-debug "CHECK_CLEAN_RETRY=$CHECK_CLEAN_RETRY"
                do-debug "INSTALL_TRY_NUMBER=$INSTALL_TRY_NUMBER"

                if [ ${CHECK_NONEXISTENT_PACKAGE:-0} -eq 0 ] && [ ${BREW_RTN_STATUS} -gt 0 ]; then

                    if [ ${CHECK_CLEAN_RETRY} -gt 0 ]; then

                        # there may have been an error with the build
                        # when im restarting a failed gcc build I get 'Error: File exists @ syserr_fail2_in'
                        brew cleanup -s ${PACKAGE}

                    fi

                    # if we haven't exhausted our job-reduce tries then decrement HOMEBREW_MAKE_JOBS and try again
                    if [ ${INSTALL_TRY_NUMBER:-1} -le ${JOB_REDUCE_MAX_TRIES:-4} ]; then

                        retry_print $ACTION $PACKAGE $(max 1 $(( $HOMEBREW_MAKE_JOBS - $(job_reduce_increment) )))
                        brew_do $ACTION $PACKAGE $FLAGS

                    # if we're at our INSTALL_TRY_NUMBER and we're still not on single threading try that before giving up
                    elif [ ${INSTALL_TRY_NUMBER:-1} -eq $((${JOB_REDUCE_MAX_TRIES:-4} + 1)) ] && [ ${HOMEBREW_MAKE_JOBS:-1} -ne 1 ]; then

                        retry_print $ACTION $PACKAGE 1
                        brew_do $ACTION $PACKAGE $FLAGS

                    # else it's failed
                    elif [ ${PACKAGE_BUILDER_NOBUILDFAIL:-0} -eq 0 ] && [ "$ACTION" != "uninstall" ]; then

                            fail_print ${ACTION} ${PACKAGE}
                            #unset INSTALL_TRY_NUMBER
                            set -e
                            exit ${BREW_RTN_STATUS}

                    # else it's failed and we dont care
                    else
                        puts-warn "Unable to ${ACTION} ${PACKAGE}. Continuing since PACKAGE_BUILDER_NOBUILDFAIL > 0 or you're doing an uninstall."
                        #unset INSTALL_TRY_NUMBER
                    fi
                fi  # see if the package actually exists and if the ACTION failed for some reason
            else  # ran out of time
                puts-warn "Not enough time to ${ACTION} ${PACKAGE}"
            fi  # check if theres time left for actual ACTION
        fi  # check if ACTION=install and the package is already installed
    else
        puts-warn "Not enough time to ${ACTION} ${PACKAGE}"
        #unset INSTALL_TRY_NUMBER
    fi
    #unset INSTALL_TRY_NUMBER
}

function brew_watch() {

    ## This thing does:
    # 1.) Traps the brew process id
    # 2.) Sends it to the background
    # 3.) Loops checking on time_remaining
    # 4.) If time_remaining==0 then kill brew with SIGTERM
    ## Why SIGTERM?
    # http://stackoverflow.com/a/690631/4106215
    # https://www.gnu.org/software/libc/manual/html_node/Program-Error-Signals.html#index-SIGABRT
    # https://www.gnu.org/software/make/manual/html_node/Interrupts.html
    # https://bash.cyberciti.biz/guide/Sending_signal_to_Processes#kill_-_send_a_signal_to_a_process
    ## Notes:
    # if anything in this trap process is f'd up then the whole thing fails
    # this is the most important part of the whole buildpack
    ## about brilliant PIPESTATUS: http://stackoverflow.com/a/1221870/4106215

    # the jobs -x thing is passing the wrong process sometimes, this gets it directly
    #declare -xi BREW_PID=$(jobs -l | grep -E '\[[0-9]+\]\+' | cut -d'+' -f2 | sed 's/^\s*\([0-9]\+\).\+/\1/')
    declare -i RTN_STATUS
    declare -i KILL_RETRIES=0
    declare -i BREW_PID=$1
    declare -i SLEEP_TIME=30
    declare -i LAST_SLEEP_TIME=${SLEEP_TIME}

    do-debug "BREW_PID=$BREW_PID"
    do-debug "jobs -l:"
    jobs -l |& indent-debug

    while [ $(kill -0 ${BREW_PID} |& grep --count .) -eq 0 ]; do  # checks if the process is still active

        local TIME_REMAINING=$(time_remaining)

        if [ ${TIME_REMAINING} -gt 0 ]; then
            if [ ${TIME_REMAINING} -le ${LAST_SLEEP_TIME} ]; then
                ## Removed the actual sleep so we exit ASAP
                #sleep ${SLEEP_TIME}  # do sleep first so it doesnt immediately print a message
                ## print fluffy messages letting them know we're still alive
                # show time remaining and check for activity more frequently as time runs out
                echo "$(countdown) ...... $(date --date=@$TIME_REMAINING +'%M:%S') remaining"
                if [ ${TIME_REMAINING} -le 120 ]; then SLEEP_TIME=20; fi
                if [ ${TIME_REMAINING} -le 60 ]; then SLEEP_TIME=10; fi
                if [ ${TIME_REMAINING} -le 30 ]; then SLEEP_TIME=5; fi
                if [ ${TIME_REMAINING} -le 10 ]; then SLEEP_TIME=1; fi
                LAST_SLEEP_TIME=$(( $TIME_REMAINING - $SLEEP_TIME ))
            fi
        else
            case $KILL_RETRIES in
            0)
                puts-warn "Out of time, aborting build with SIGTERM"
                (set -x; kill -SIGTERM ${BREW_PID} || true)
            ;;
            1)
                puts-warn "Aborting build with SIGINT"
                (set -x; kill -SIGINT ${BREW_PID} || true)
            ;;
            *)
                puts-warn "Aborting build with SIGKILL"
                (set -x; kill -SIGKILL ${BREW_PID} || true)
            ;;
            esac
            sleep 5  # wait for the kill signal to work
            RTN_STATUS=0  # so it doesn't retry in brew_do
            KILL_RETRIES=$(( $KILL_RETRIES + 1 ))
        fi
    done

    do-debug "Waiting on brew return status"
    wait ${BREW_PID}
    WAIT_RTN_STATUS=$?
    do-debug "wait return status = $WAIT_RTN_STATUS"
    RTN_STATUS=${RTN_STATUS:-$WAIT_RTN_STATUS}
    do-debug "Leaving brew_watch with RTN_STATUS = $RTN_STATUS"
    return ${RTN_STATUS}
}

function brew_checkfor() {
    brew list | grep --count "$1" || true
}

function brew_install_defaults() {
    # install core tools
    if [ ${PACKAGE_BUILDER_NOINSTALL_DEFAULTS:-0} -ne 1 ]; then

        puts-step "Installing core tools"

        # gcc & glibc wont install without a newer gawk
        if [ ${PACKAGE_BUILDER_NOINSTALL_GAWK:-0} -ne 1 ] && [ $(brew_checkfor gawk) -eq 0 ]; then
            puts-step "Installing gawk"
            # these dont show up as dependencies but they are
            brew_do install patchelf
            brew_do install pkg-config
            brew_do install xz
            brew_do install gawk
        fi

        if [ ${PACKAGE_BUILDER_NOINSTALL_GCC:-0} -ne 1 ] && [ $(brew_checkfor gcc) -eq 0 ]; then
            puts-step "Installing GCC"
            # these dont show up as dependencies but they are
            brew_do install binutils
            brew_do install linux-headers
            brew_do install glibc
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
    local TEST='
    {
        if($0 ~ /Error: No such keg: /) {
            print "nonexistent_package" > "/tmp/brew_test_results.txt";
        }
        else if($0 ~ /Error: No available formula with the name /) {
            print "nonexistent_package" > "/tmp/brew_test_results.txt";
        }
        else if($0 ~ /Error: No formulae found in taps/) {
            print "nonexistent_package" > "/tmp/brew_test_results.txt";
        }
        else if($0 ~ /Error: File exists /) {
            print "clean_and_retry" > "/tmp/brew_test_results.txt";
        }
        print $0;
        system("");
    }'

    awk "$TEST" | indent
}
