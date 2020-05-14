#!/bin/bash

FILE=$1

for ((;;))
do
	cat $FILE > /dev/null
done
