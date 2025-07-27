#!/bin/bash
# This script runs Ruby files with the RAAF gem load paths set up

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Build the Ruby include paths
RUBY_INCLUDES=""
for gem in core tracing memory guardrails providers tools dsl rails analytics compliance debug misc streaming; do
  if [ -d "$ROOT_DIR/$gem/lib" ]; then
    RUBY_INCLUDES="$RUBY_INCLUDES -I$ROOT_DIR/$gem/lib"
  fi
done

# Also add main lib if it exists
if [ -d "$ROOT_DIR/lib" ]; then
  RUBY_INCLUDES="$RUBY_INCLUDES -I$ROOT_DIR/lib"
fi

# Run the Ruby file with the include paths
exec ruby $RUBY_INCLUDES "$@"