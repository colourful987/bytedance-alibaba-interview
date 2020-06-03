#!/bin/bash

ls | grep -v README.md | grep -v create_list.sh | xargs -I{} echo "* [ ] ["{}"](./"{}")" > README.md
