# Start first making sure modules stay disabled when loaded
<<EOF > $CONF
DEBUG=1
typeset -ga DEBUG_TRACE_FUNCS
DEBUG_TRACE_FUNCS=($TRACE_FUNCS)
source $SRC_DIR/modules/debug.sh

typeset -g URL_REWRITE=0
typeset -g CGI_ENABLE=0
typeset -g COMPRESS=0
typeset -g IP_MATCH=0

typeset -gA URL_PATTERNS
URL_PATTERNS=( "/file.txt" "/.dot.txt" )

typeset -g CGI_EXTS="sh"

source $SRC_DIR/modules/url_rewrite.sh
source $SRC_DIR/modules/cgi.sh
source $SRC_DIR/modules/compress.sh
EOF
reload_conf

# Disabled url_rewrite
describe "URL rewrite is loaded but disabled"
check 127.0.0.1:$PORT/file.txt \
      --http_code 200 \
      --file_compare $TESTROOT/file.txt \
      --header_compare 'Content-type: text/plain'

# Disabled gzip
describe "Compressed loaded but disabled"
check --header 'Accept-Encoding: gzip' 127.0.0.1:$PORT \
      --http_code 200 \
      --header_compare 'Content-Encoding: ^(?!.*gzip).*$'

<<EOF > $TESTROOT/test_app.sh
#!/bin/zsh
print "Content-type: text/plain\n\n"
print "Hello World"
EOF
chmod +x $TESTROOT/test_app.sh

# Disabled cgi
describe "CGI is loaded but disabled"
check 127.0.0.1:$PORT/test_app.sh \
      --http_code 200 \
      --file_compare $TESTROOT/test_app.sh

###
# Enable url_rewrite
<<EOF > $CONF
DEBUG=1
typeset -ga DEBUG_TRACE_FUNCS
DEBUG_TRACE_FUNCS=($TRACE_FUNCS)
source $SRC_DIR/modules/debug.sh

MAX_CONN=12
PORT=$PORT
IP_REDIRECT="127.0.0.1"
HTTP_KEEP_ALIVE=1
HTTP_TIMEOUT=2
HTTP_RECV_TIMEOUT=1
HTTP_BODY_SIZE=16384
HTTP_CACHE=0
INDEX_FILE=0
HIDDEN_FILES=1
FOLLOW_SYMLINKS=0
CACHE=1
LOG_FILE=/dev/null

typeset -g COMPRESS=0
typeset -g CGI_ENABLE=0
typeset -g URL_REWRITE=1

typeset -gA URL_PATTERNS
URL_PATTERNS=( "/file.txt" "/.dot.txt" )
source $SRC_DIR/modules/url_rewrite.sh
EOF
reload_conf

describe "URL rewrite"
check 127.0.0.1:$PORT/file.txt \
      --http_code 200 \
      --file_compare $TESTROOT/.dot.txt \
      --header_compare 'Content-type: text/plain'

###
# Enable gzip
<<EOF > $CONF
DEBUG=1
typeset -ga DEBUG_TRACE_FUNCS
DEBUG_TRACE_FUNCS=($TRACE_FUNCS)
source $SRC_DIR/modules/debug.sh

URL_REWRITE=0
CGI_ENABLE=0
COMPRESS=1

typeset -g COMPRESS_TYPES="text/html,text/plain"
typeset -g COMPRESS_LEVEL=6
typeset -g COMPRESS_MIN_SIZE=100
typeset -g COMPRESS_CACHE=1
source $SRC_DIR/modules/compress.sh
EOF
reload_conf

for i in {1..1000}; str+="lorem ipsum "

print $str > $TESTROOT/compress.txt
gzip -k -6 $TESTROOT/compress.txt

describe "Compress file request"
check --header 'Accept-Encoding: gzip' 127.0.0.1:$PORT/compress.txt \
      --http_code 200 \
      --file_compare $TESTROOT/compress.txt.gz \
      --header_compare 'Content-Encoding: gzip'

describe "Compress dir request"
check --header 'Accept-Encoding: gzip' 127.0.0.1:$PORT \
      --http_code 200 \
      --header_compare 'Content-Encoding: gzip'

describe "Cached dir request"
check --header 'Accept-Encoding: gzip' 127.0.0.1:$PORT \
      --header_compare 'Content-Length: [0-9]'

rm $TESTROOT/compress.txt $TESTROOT/compress.txt.gz

###
# Enable CGI Module
<<EOF > $CONF
DEBUG=1
typeset -ga DEBUG_TRACE_FUNCS
DEBUG_TRACE_FUNCS=($TRACE_FUNCS)
source $SRC_DIR/modules/debug.sh

URL_REWRITE=0
COMPRESS=0
CGI_ENABLE=1

typeset -g CGI_EXTS="sh"
typeset -g CGI_TIMEOUT=2
source $SRC_DIR/modules/cgi.sh
EOF
reload_conf

<<EOF > $TESTROOT/test_app.sh
#!/bin/zsh
print "Content-type: text/plain\n\n"
print "Hello World"
EOF
chmod +x $TESTROOT/test_app.sh

<<EOF > $TESTROOT/test_app_fail1.sh
#!/bin/zsh
print "Content-type: text/plain\n\n"
sleep 7
print "foo"
EOF
chmod +x $TESTROOT/test_app_fail1.sh

<<EOF > $TESTROOT/test_app_fail2.sh
#!/bin/zsh
print
print "foo"
EOF
chmod +x $TESTROOT/test_app_fail2.sh

describe "Test cgi script"
check 127.0.0.1:$PORT/test_app.sh \
      --http_code 200 \
      --size_download 13

describe "Test cgi script fail by timeout"
check 127.0.0.1:$PORT/test_app_fail1.sh \
      --http_code 500

describe "Test cgi script fail by content-type"
check 127.0.0.1:$PORT/test_app_fail2.sh \
      --http_code 500

rm $TESTROOT/*.sh

###
# Finally, test ip match module.
#
# Now this is pretty dumb, so hold with me. The IP match module will
# never reject a connection from localhost. So, in order to test it we
# try to find a local ip address. If we can't, simply print a warning
# message instead of crashing our tests.
case $OSTYPE in
    (linux*)
        ip=$(hostname -I | awk '{ print $1 }');;
    (darwin*|*bsd*)
        ip=$(ifconfig | awk '$1 == "inet" && $2 != "127.0.0.1" { print $2 }');;
esac

if [[ -z $ip || ip == "127.0.0.1" ]]; then
    print "Unable to find suitable IP, skipping IP match tests..."
    return
fi

<<EOF > $CONF
DEBUG=1
typeset -ga DEBUG_TRACE_FUNCS
DEBUG_TRACE_FUNCS=($TRACE_FUNCS)
source $SRC_DIR/modules/debug.sh

URL_REWRITE=0
COMPRESS=0
CGI_ENABLE=0
IP_MATCH=1

source $SRC_DIR/modules/ip_match.sh
EOF
reload_conf

describe "Accept all IPs"
check $ip:$PORT/ \
      --http_code 200

<<EOF > $CONF
DEBUG=1
typeset -ga DEBUG_TRACE_FUNCS
DEBUG_TRACE_FUNCS=($TRACE_FUNCS)
source $SRC_DIR/modules/debug.sh

URL_REWRITE=0
COMPRESS=0
CGI_ENABLE=0

IP_MATCH=1
IP_ACCEPT=127.0.0.1

source $SRC_DIR/modules/ip_match.sh
EOF
reload_conf

describe "Reject unmatched ip"
check $ip:$PORT/file.txt \
      --fail

<<EOF > $CONF
DEBUG=1
typeset -ga DEBUG_TRACE_FUNCS
DEBUG_TRACE_FUNCS=($TRACE_FUNCS)
source $SRC_DIR/modules/debug.sh

URL_REWRITE=0
COMPRESS=0
CGI_ENABLE=0

IP_MATCH=1
IP_ACCEPT='${ip%.*}.*'

source $SRC_DIR/modules/ip_match.sh
EOF
reload_conf

describe "Accept matched ip"
check $ip:$PORT/file.txt \
      --http_code 200

describe "Accept localhost"
check 127.0.0.1:$PORT/file.txt \
      --http_code 200
