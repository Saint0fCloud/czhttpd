#!/usr/bin/env zsh
#
# Stress test/benchmark czhttpd using vegeta
# (https://github.com/tsenart/vegeta)
###

autoload colors
(( $terminfo[colors] >= 8)) && colors

setopt err_return

which vegeta >/dev/null || error "Missing vegeta, unable to run stress tests"

typeset -g VEGETA_OPTS VERBOSE DURATION

# Output directories
readonly -g STRESS_DIR=${0:A:h}
readonly -g REPORT_DIR=$STRESS_DIR/report
readonly -g HTML_DIR=$STRESS_DIR/html

source $STRESS_DIR/../utils.sh

mkdir -p $TESTTMP $TESTROOT
: >> $CONF

function help() {
<<EOF
czhttpd stress test script

Options:
    -d | --duration   Vegeta attack duration (default: 5s)
    -l | --log        Redirect czhttpd output to given file
    -p | --port       Port to pass to czhttpd (Default: 8080)
    -v | --verbose    Enable verbose output
EOF

exit
}

function attack() {
    echo "GET http://127.0.0.1:$PORT/" | \
        vegeta attack -name=$1 "${=VEGETA_OPTS}" > $REPORT_DIR/$1.bin

    (( VERBOSE )) && vegeta report $REPORT_DIR/$1.bin

    return 0
}

function describe() {
    (( VERBOSE )) && print "$fg_bold[blue]$*$fg_no_bold[white]"

    return 0
}

zparseopts -D -A opts -duration: d: -verbose v -log: l: -port: p: -help h || error "Failed to parse args"

for i in ${(k)opts}; do
    case $i in
        ("--duration|-d")
            DURATION=$opts[$i];;
        ("--verbose"|"-v")
            VERBOSE=1;;
        ("--log"|"-l")
            : >> $opts[$i] 2>/dev/null || error "Invalid logfile"
            exec {debugfd}>>$opts[$i];;
        ("--port"|"-p")
            if [[ $opts[$i] == <-> ]]; then
                typeset -g PORT=$opts[$i]
            else
                error "Invalid port $opts[$i]"
            fi;;
        ("--help"|"-h")
            help;;
    esac
done

(( ! debugfd )) && exec {debugfd}>/dev/null
: ${DURATION:="5s"}
: ${VERBOSE:=0}

VEGETA_OPTS="-duration=$DURATION -http2=false -timeout=10s"

# Preserve TESTROOT across tests
root=$TESTROOT
readonly -g root

# For single file stress tests
for i in {1..1000}; str+="lorem ipsum"
print $str > $TESTROOT/test.html

# For directory listing stress tests
for i in {a..z}; print -n "Hello World!" > $TESTROOT/$i.html

# Prep output directories
mkdir -p $REPORT_DIR $HTML_DIR
rm -rf $REPORT_DIR/*.bin(N) $HTML_DIR/*.html(N)

for i in ${1:-$STRESS_DIR/*.profile}; do
    print "$fg_bold[magenta]${i:t}$fg_no_bold[white]"
    source $i
done

vegeta plot $REPORT_DIR/*.bin > $HTML_DIR/full.html