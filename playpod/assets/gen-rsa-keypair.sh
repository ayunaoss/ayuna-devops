#!/bin/bash

ssh-keygen -q -t rsa -f $(pwd)/id_rsa -N '' -C ayuna-playpod
