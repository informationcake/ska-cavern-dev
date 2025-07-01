#!/bin/bash
set -e

# $ARGS: custom args to be set (see `uvicorn --help`)
exec uvicorn prepare_data.main:app --host 0.0.0.0 $ARGS
