#!/bin/bash

until $(./paradigma-server.pl -l | ./send.py); do
  echo '"./paradigma-server.pl -l | ./send.py" failed, restarting...' > &2
  sleep 1
done

