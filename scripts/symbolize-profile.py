#!/usr/bin/env python3
"""Rank one thread of a macOS `sample` profile and name GMSE01 code.

usage: symbolize-profile.py <sample.txt> [--map GMSE01.map] [--thread NAME]
                            [--top N] [--callers SYMBOL]

Generated module symbols are named by guest address: loop_80348814 is a loop at
that address, func_80361600 is the 16 KiB chunk that starts there. With a map
from fetch-gmse01-symbols.sh, loops become function+offset and chunks list the
game functions they cover.
"""
import argparse
import bisect
import collections
import re
import sys

NODE = re.compile(r'^(\s*)([+!:| ]*?)(\d+) (.+?)  \(in ([^)]+)\)')
THREAD = re.compile(r'^\s+\d+ Thread_')
CHUNK = 0x4000


def load_map(path):
    rows = []
    for line in open(path):
        addr, size, name = line.split(maxsplit=2)
        rows.append((int(addr, 16), int(size, 16), name.strip()))
    rows.sort()
    return rows


def name_for(symbol, functions):
    if not functions:
        return symbol
    starts = [f[0] for f in functions]
    m = re.fullmatch(r'loop_([0-9A-Fa-f]{8})', symbol)
    if m:
        addr = int(m.group(1), 16)
        i = bisect.bisect_right(starts, addr) - 1
        if i >= 0 and addr < functions[i][0] + functions[i][1]:
            return '%s (%s+0x%x)' % (symbol, functions[i][2], addr - functions[i][0])
        return symbol
    m = re.fullmatch(r'func_([0-9A-Fa-f]{8})', symbol)
    if m:
        lo = int(m.group(1), 16)
        lo_i = bisect.bisect_right(starts, lo) - 1
        if lo_i < 0 or functions[lo_i][0] + functions[lo_i][1] <= lo:
            lo_i += 1  # the preceding function ends before this chunk
        hi_i = bisect.bisect_left(starts, lo + CHUNK)
        names = [f[2] for f in functions[lo_i:hi_i]]
        shown = ', '.join(names[:3]) + (', +%d more' % (len(names) - 3) if len(names) > 3 else '')
        return '%s [%08x-%08x: %s]' % (symbol, lo, lo + CHUNK, shown)
    return symbol


def thread_nodes(lines, thread):
    start = next((i for i, l in enumerate(lines) if THREAD.match(l) and thread in l), None)
    if start is None:
        sys.exit('thread not found: ' + thread)
    for line in lines[start + 1:]:
        if THREAD.match(line) or not line.strip():
            return
        m = NODE.match(line)
        if m:
            name = re.sub(r' \+ [\d,.]+.*$', '', m.group(4)).strip()
            yield len(m.group(1)) + len(m.group(2)), int(m.group(3)), name, m.group(5)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sample')
    ap.add_argument('--map')
    ap.add_argument('--thread', default='CPU-GPU thread')
    ap.add_argument('--top', type=int, default=30)
    ap.add_argument('--callers')
    args = ap.parse_args()
    functions = load_map(args.map) if args.map else []
    lines = open(args.sample).read().split('\n')

    stack, total = [], 0
    self_time, callers = collections.Counter(), collections.Counter()

    def pop(depth):
        while stack and stack[-1][0] >= depth:
            _, count, name, lib, children = stack.pop()
            self_time[(name, lib)] += count - children

    for depth, count, name, lib in thread_nodes(lines, args.thread):
        pop(depth)
        if stack:
            stack[-1][4] += count
        else:
            total += count
        if args.callers and re.sub(r'\(.*', '', name) == args.callers:
            callers[' < '.join(re.sub(r'\(.*', '', s[2]) for s in reversed(stack[-8:]))] += count
        stack.append([depth, count, name, lib, 0])
    pop(-1)
    if not total:
        sys.exit('no samples for thread')

    print('%s: %d samples' % (args.thread, total))
    if args.callers:
        for chain, count in callers.most_common(args.top):
            print('%6.2f%%  %s' % (100.0 * count / total, chain))
        return
    for (name, lib), count in self_time.most_common(args.top):
        print('%6.2f%%  %s  (%s)' % (100.0 * count / total, name_for(name, functions), lib))


if __name__ == '__main__':
    main()
