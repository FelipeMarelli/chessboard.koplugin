#!/bin/sh
# Runs the KOReader emulator with the plugin, sized like a Paperwhite at half scale.
# usage: ./run-emu.sh [book]
DIR="$(dirname "$(realpath "$0")")"
export KO_HOME="$DIR/emu-data"
export EMULATE_READER_W="${EMULATE_READER_W:-632}"
export EMULATE_READER_H="${EMULATE_READER_H:-840}"
export EMULATE_READER_DPI="${EMULATE_READER_DPI:-150}"
exec "$DIR/vendor/koreader-emu/bin/koreader" "$@"
