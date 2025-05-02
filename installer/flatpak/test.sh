#!/bin/bash
echo "Test Script Started!" > "$1"
echo "Arguments received:" >> "$1"
echo "Arg1: $1" >> "$1"
echo "--- End Test Script ---" >> "$1"
exit 0
