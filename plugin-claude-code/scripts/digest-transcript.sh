#!/bin/sh
# digest-transcript.sh — Extract high-signal content from a session transcript
# Produces a markdown digest at ~10-20% of original token cost
#
# Usage: bash digest-transcript.sh <transcript.jsonl> [output.md]
# If output is omitted, writes to stdout
#
# Extracts:
#   - All user messages (verbatim — they're short and high-value)
#   - First 5 + last 5 lines of each assistant text block
#   - All Insight blocks (★ Insight pattern)
#   - Lines containing signal keywords (decided, alternative, correction, etc.)

INPUT="$1"
OUTPUT="$2"

if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "Usage: digest-transcript.sh <transcript.jsonl> [output.md]" >&2
  exit 1
fi

# Extract digest using python3 for reliable JSON parsing
DIGEST=$(python3 -c "
import json, sys, re

SIGNAL_WORDS = re.compile(
    r'\b(decided|decision|alternative|chose|chosen|rejected|correction|'
    r'lesson|pattern|surprised|unexpected|tradeoff|trade-off|feedback|'
    r'confirmed|insight|approach|architecture|migration|breaking change|'
    r'wont fix|wont do|should not|must not|never|always)\b',
    re.IGNORECASE
)

user_messages = []
assistant_summaries = []
insight_blocks = []
signal_lines = []

turn_num = 0

with open('$INPUT') as f:
    for line in f:
        try:
            obj = json.loads(line.strip())
        except json.JSONDecodeError:
            continue

        msg_type = obj.get('type')
        if msg_type not in ('user', 'assistant'):
            continue

        turn_num += 1
        msg = obj.get('message', {})
        content = msg.get('content', [])

        # Extract text from content
        if isinstance(content, str):
            text = content.strip()
        elif isinstance(content, list):
            parts = []
            for block in content:
                if isinstance(block, dict) and block.get('type') == 'text':
                    parts.append(block.get('text', ''))
                elif isinstance(block, str):
                    parts.append(block)
            text = '\n'.join(parts).strip()
        else:
            continue

        if not text:
            continue

        if msg_type == 'user':
            # User messages: keep fully (they're short)
            user_messages.append((turn_num, text))

        elif msg_type == 'assistant':
            lines = text.split('\n')

            # Check for Insight blocks
            in_insight = False
            insight_buf = []
            for l in lines:
                if 'Insight' in l and '───' in l:
                    in_insight = True
                    insight_buf.append(l)
                elif in_insight:
                    insight_buf.append(l)
                    if '───' in l and len(insight_buf) > 1:
                        insight_blocks.append((turn_num, '\n'.join(insight_buf)))
                        in_insight = False
                        insight_buf = []

            # First 5 + last 5 lines (skip if short enough to include fully)
            if len(lines) <= 12:
                summary = '\n'.join(lines)
            else:
                first = '\n'.join(lines[:5])
                last = '\n'.join(lines[-5:])
                summary = first + '\n[...]\n' + last
            assistant_summaries.append((turn_num, summary))

            # Signal keyword lines
            for l in lines:
                if SIGNAL_WORDS.search(l) and len(l.strip()) > 20:
                    # Skip lines that are just code or tool output
                    stripped = l.strip()
                    if stripped[0] in ('\x60', '{', '[', '|', '-', '#'):
                        continue
                    signal_lines.append((turn_num, stripped))

# Output markdown digest
print('# Session Digest')
print()

if user_messages:
    print('## User Messages')
    print()
    for turn, text in user_messages:
        # Truncate very long user messages (e.g., pasted content)
        if len(text) > 500:
            text = text[:500] + ' [truncated]'
        print(f'**Turn {turn}:** {text}')
        print()

if assistant_summaries:
    print('## Assistant Summaries')
    print()
    for turn, text in assistant_summaries:
        print(f'**Turn {turn}:**')
        print(text)
        print()

if insight_blocks:
    print('## Insight Blocks')
    print()
    for turn, text in insight_blocks:
        print(f'**Turn {turn}:**')
        print(text)
        print()

if signal_lines:
    print('## Signal Lines')
    print()
    seen = set()
    for turn, text in signal_lines:
        if text not in seen:
            seen.add(text)
            print(f'- [T{turn}] {text}')
    print()

# Stats
total_user = sum(len(t) for _, t in user_messages)
total_assist = sum(len(t) for _, t in assistant_summaries)
total_insight = sum(len(t) for _, t in insight_blocks)
total_signal = sum(len(t) for _, t in signal_lines)
total = total_user + total_assist + total_insight + total_signal
print(f'---')
print(f'Digest stats: {len(user_messages)} user msgs, {len(assistant_summaries)} assistant summaries, {len(insight_blocks)} insight blocks, {len(signal_lines)} signal lines')
print(f'Digest size: ~{total} chars (~{total // 4} tokens)')
" 2>/dev/null)

if [ -z "$DIGEST" ]; then
  echo "Error: digest extraction failed (python3 may not be available or transcript is malformed)" >&2
  exit 1
fi

if [ -n "$OUTPUT" ]; then
  echo "$DIGEST" > "$OUTPUT"
else
  echo "$DIGEST"
fi
