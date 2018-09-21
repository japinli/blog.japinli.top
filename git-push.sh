#!/bin/bash

echo "Add files ..."
git add .
echo -n "Prepare to commit ... Write a commit message (optional): "
read remarks
if [ ! -n "$remarks" ]; then
    remarks="Update: $(date +%F\ %T)"
fi

git commit -m "$remarks"
echo "Commiting code ..."
git push
