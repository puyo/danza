require 'socket'
require 'json'

s = TCPSocket.new 'localhost', 8787
instructions = s.gets
s.puts ARGV[0] || 'Alice'

loop do
  line = s.gets
  break if line.nil?
  state = JSON.parse(line)
  print state['beat'], ': '
  p state
  direction = %w(up down left right stay).sample
  response = {
    direction: direction,
    beat: state['beat'],
  }.to_json
  s.puts response
end

s.close
