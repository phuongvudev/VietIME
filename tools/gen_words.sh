#!/bin/bash
# In ra các từ trong candidates.txt mà Telex vô tình biến thành âm tiết tiếng Việt hợp lệ.
# Dùng để cập nhật VietEngine/Sources/CVietEngine/english_words.c (nhớ bỏ các từ mà chữ
# tiếng Việt tương ứng quá phổ biến, vd sex→sẽ, car→cả, cos→có).
set -e
cd "$(dirname "$0")/.."
cc -std=c99 -O1 -I VietEngine/Sources/CVietEngine/include \
  VietEngine/Sources/CVietEngine/viet_engine.c VietEngine/Sources/CVietEngine/english_doubles.c VietEngine/Sources/CVietEngine/context.c tools/empty_words.c tools/collisions.c -o /tmp/ve_coll
tr ' ' '\n' < tools/candidates.txt | grep -v '^$' | sort -u | /tmp/ve_coll "$@"
