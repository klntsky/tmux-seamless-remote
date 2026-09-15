function abs(value) { return value < 0 ? -value : value }

BEGIN { best_edge = 1e9; best_delta = 1e9 }

$1 == "PANE" {
  id = $2
  x = $3
  y = $4
  width = $5
  height = $6
  window_width = $7
  window_height = $8
  ref_x = window_width * (point_x - dx) / dw
  ref_y = window_height * (point_y - dy) / dh

  if (direction == "right") {
    edge = x
    delta = abs(y + height / 2 - ref_y)
  } else if (direction == "left") {
    edge = window_width - (x + width)
    delta = abs(y + height / 2 - ref_y)
  } else if (direction == "down") {
    edge = y
    delta = abs(x + width / 2 - ref_x)
  } else {
    edge = window_height - (y + height)
    delta = abs(x + width / 2 - ref_x)
  }

  if (edge < best_edge || (edge == best_edge && delta < best_delta)) {
    best = id
    best_edge = edge
    best_delta = delta
  }
}

END { if (best != "") print best }
