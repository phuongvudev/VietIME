#!/bin/bash
# Gõ thử toàn bộ tools/corpus_vi.txt theo nhiều kiểu (cần python3).
set -e
cd "$(dirname "$0")/.."
E=VietEngine/Sources/CVietEngine
cc -O1 -I $E/include $E/*.c tools/batch.c -o /tmp/ve_batch
cc -O1 -I $E/include $E/*.c tools/batch2.c -o /tmp/ve_batch2
cc -O1 -I $E/include $E/*.c tools/batch3.c -o /tmp/ve_batch3
for m in std tone_early mods_end; do printf "Telex %-11s " $m; python3 tools/gen_typings.py $m tools/corpus_vi.txt | /tmp/ve_batch prose; done
printf "VNI               "; python3 tools/gen_typings.py vni tools/corpus_vi.txt | /tmp/ve_batch vni prose
for g in upper random backspace; do printf "%-17s " $g; python3 tools/stress.py $g | /tmp/ve_batch2 prose; done
printf "sửa dấu tại chỗ   "; python3 tools/gen_edit.py | /tmp/ve_batch3
