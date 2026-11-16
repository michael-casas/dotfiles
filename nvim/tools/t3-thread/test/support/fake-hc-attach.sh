#!/bin/sh
# Synthetic stand-in for `hc attach --history N <addr>`: the control-sequence
# shape a real herdr-core viewer opens with (soft reset, leave the alternate
# screen, home, clear), then history rows and blank rows with the DEFAULT
# background only - no colour of its own. Captured shape, synthetic text.
printf '\033[!p\033[?1049l\033[H\033[2J'
i=0
while [ "$i" -lt 12 ]; do
  printf 'PEN_ROW_%s plain text\r\n\r\n' "$i"
  i=$((i + 1))
done
i=0
while [ "$i" -lt 40 ]; do
  printf 'tail %s\r\n' "$i"
  i=$((i + 1))
done
printf 'PEN_READY\r\n'
exec sleep 3600
