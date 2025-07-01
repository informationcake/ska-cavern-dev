#!/bin/bash

env

celery -A src.prepare_data.tasks worker -l INFO -c 1
