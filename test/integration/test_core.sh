# Set our default config vars in each testfile rather than `test.sh` so that we
# can guarantee the env no matter what order the tests are run.
<<EOF > $CONF
DEBUG=1
typeset -ga DEBUG_TRACE_FUNCS
DEBUG_TRACE_FUNCS=($TRACE_FUNCS)
source $SRC_DIR/modules/debug.sh

MAX_CONN=1
PORT=$PORT
IP_REDIRECT="127.0.0.1"
HTTP_KEEP_ALIVE=1
HTTP_TIMEOUT=2
HTTP_RECV_TIMEOUT=1
HTTP_BODY_SIZE=16384
INDEX_FILE=index.html
HIDDEN_FILES=0
FOLLOW_SYMLINKS=0
CACHE=0
LOG_FILE="/dev/null"
EOF
reload_conf

# Let's check normal file/dir serving first with a default conf
describe "Check index file"
check --header 'keep-alive' 127.0.0.1:$PORT \
      --http_code 200 \
      --file_compare $TESTROOT/index.html \
      --header_compare 'Content-type: text/html'

for i in {file,file_pröva,file\ space}.txt; do
    describe "Normal request for $i"
    check 127.0.0.1:$PORT/$i \
          --http_code 200 \
          --file_compare $TESTROOT/$i \
          --header_compare 'Content-type: text/plain'
done

describe "Check directory request"
check 127.0.0.1:$PORT/dir/ \
      --http_code 200 \
      --header_compare 'Transfer-Encoding: chunked'

describe "HEAD should not send anything"
check --method "HEAD" 127.0.0.1:$PORT/file.txt \
      --http_code 200 \
      --size_download 0

# Let's go up the chain of http error codes
describe "Redirection"
check 127.0.0.1:$PORT/dir \
      --http_code 301

describe "Incomplete request line"
check --method " " 127.0.0.1:$PORT \
      --http_code 400

describe "Dot file disabled request"
check 127.0.0.1:$PORT/.dot.txt \
      --http_code 403

describe "Symbolic link disabled request"
check 127.0.0.1:$PORT/link \
      --http_code 403

describe "Nonexistent file/dir"
check 127.0.0.1:$PORT/foo \
      --http_code 404

describe "POST should only be accepted by cgi"
check --method "POST" 127.0.0.1:$PORT/ \
      --http_code 405

describe "Test unknown method"
check --method "PUT" 127.0.0.1:$PORT \
      --http_code 501

describe "HTTP/1.0 request"
check --http 1.0 127.0.0.1:$PORT \
      --http_code 505

# What about if-modified-since and if-unmodified-since
describe "Request unmodified file"
check --header "If-Modified-Since: $(unixtime)" 127.0.0.1:$PORT/file.txt \
      --http_code 304

describe "Request modified file"
check --header "If-Modified-Since: $(unixtime 20)" 127.0.0.1:$PORT/file.txt \
      --http_code 200

describe "Send if unmodified"
check --header "If-Unmodified-Since: $(unixtime)" 127.0.0.1:$PORT/file.txt \
      --http_code 200

describe "412 file modified"
check --header "If-Unmodified-Since: $(unixtime 40000)" 127.0.0.1:$PORT/file.txt \
      --http_code 412

describe "Invalid time for if-modified-since"
check --header "If-Modified-Since: $(date)" 127.0.0.1:$PORT/file.txt \
      --http_code 200

# Finally, check that our headers are being set properly
describe "Client Connection: close"
check --header 'Connection: close' 127.0.0.1:$PORT \
      --http_code 200 \
      --header_compare 'Connection: close'

describe "Client Connection: keep-alive"
check --header 'Connection: keep-alive' 127.0.0.1:$PORT \
      --http_code 200 \
      --header_compare 'Connection: keep-alive'

describe "Server header"
check --header 'Host: SuperAwesomeServ' 127.0.0.1:$PORT \
      --http_code 200 \
      --header_compare 'Server: czhttpd'

rm $TESTROOT/index.html

# Restart our server so that DOCROOT is pointing to a single file
stop_server
TESTROOT=$TESTROOT/file.txt
start_server
heartbeat

describe "Check serving single file"
check 127.0.0.1:$PORT \
      --http_code 200 \
      --file_compare $TESTROOT \
      --header_compare 'Content-type: text/plain'

stop_server
TESTROOT=/tmp/czhttpd-test
start_server
heartbeat

<<EOF > $CONF
DEBUG=1
typeset -ga DEBUG_TRACE_FUNCS
DEBUG_TRACE_FUNCS=($TRACE_FUNCS)
source $SRC_DIR/modules/debug.sh

MAX_CONN=0
HTTP_KEEP_ALIVE=0
EOF
reload_conf

describe "Keep alive disabled"
check --header 'Connection: keep-alive' 127.0.0.1:$PORT \
      --header_compare 'Connection: close'

describe "Check maxed out connections"
check 127.0.0.1:$PORT \
      --http_code 503

# Let's enable some non-default config options
<<EOF > $CONF
DEBUG=1
typeset -ga DEBUG_TRACE_FUNCS
DEBUG_TRACE_FUNCS=($TRACE_FUNCS)
source $SRC_DIR/modules/debug.sh

MAX_CONN=4
HTTP_KEEP_ALIVE=1
HTTP_BODY_SIZE=5
HIDDEN_FILES=1
FOLLOW_SYMLINKS=1
CACHE=1
EOF
reload_conf

# Let's check that czhttpd is caching html files. The only way really is to see
# if the file is being sent with fixed length rather than chunked.
describe "Cache request"
check 127.0.0.1:$PORT \
      --http_code 200 \
      --header_compare 'Content-length: [0-9]'

describe "Enabled hidden files request"
check 127.0.0.1:$PORT/.dot.txt \
      --http_code 200 \
      --file_compare $TESTROOT/.dot.txt \
      --header_compare 'Content-type: text/plain'

describe "Enabled symbolic link request"
check 127.0.0.1:$PORT/link \
      --http_code 200 \
      --file_compare $TESTROOT/file.txt \
      --header_compare 'Content-type: text/plain'

# Check parsing request message body
describe "Fixed request body too large"
check --data 'Hello World!' 127.0.0.1:$PORT \
      --http_code 413

describe "Fixed request body smaller than content-length"
check --data 'HH' --header 'Content-length: 3' 127.0.0.1:$PORT \
      --http_code 400

describe "Fixed request body just right"
check --data 'HH' 127.0.0.1:$PORT \
      --http_code 200

describe "Chunked request body too large"
check --chunked --data 'Hello World!' 127.0.0.1:$PORT \
      --http_code 413

describe "Chunked request body just right"
check --chunked --data 'HH' 127.0.0.1:$PORT \
      --http_code 200
