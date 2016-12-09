module GosuExt
  def draw_circle(x, y, radius, col, bg_col, segments: 32)
    coef = 2.0 * Math::PI / segments
    verts = []
    segments.times do |n|
      rads = n * coef
      verts << [radius * Math.cos(rads) + x, radius * Math.sin(rads) + y]
    end
    each_edge(verts) do |a, b|
      draw_triangle(x, y, bg_col, a[0], a[1], bg_col, b[0], b[1], bg_col)
      draw_line(a[0], a[1], col, b[0], b[1], col)
    end
  end

  def draw_rect(x, y, w, h, col, layer)
    draw_triangle(x, y, col, x + w, y, col, x, y + h, col)
    draw_triangle(x + w, y, col, x + w, y + h, col, x, y + h, col)
  end

  def each_edge(arr)
    arr.size.times do |n|
      yield arr[n], arr[(n + 1) % arr.size]
    end
  end
end
