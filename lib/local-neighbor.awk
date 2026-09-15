function abs(value) { return value < 0 ? -value : value }

BEGIN { best_gap = 1e9; best_delta = 1e9 }

{
  id = $1
  x = $2
  y = $3
  width = $4
  height = $5
  valid = 0

  if (direction == "left" && x + width <= sx) {
    gap = sx - (x + width)
    delta = abs(y + height / 2 - ref_y)
    valid = 1
  } else if (direction == "right" && x >= sx + sw) {
    gap = x - (sx + sw)
    delta = abs(y + height / 2 - ref_y)
    valid = 1
  } else if (direction == "up" && y + height <= sy) {
    gap = sy - (y + height)
    delta = abs(x + width / 2 - ref_x)
    valid = 1
  } else if (direction == "down" && y >= sy + sh) {
    gap = y - (sy + sh)
    delta = abs(x + width / 2 - ref_x)
    valid = 1
  }

  if (valid && (gap < best_gap || (gap == best_gap && delta < best_delta))) {
    best = id
    best_gap = gap
    best_delta = delta
  }
}

END { if (best != "") print best }
