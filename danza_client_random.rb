require 'socket'
require 'json'

s = TCPSocket.new 'localhost', 8787
instructions = s.gets
puts 'CLIENT INSTRUCTIONS:'
puts instructions
puts
s.puts ARGV[0] || 'Rando'

loop do
  line = s.gets
  break if line.nil?
  state = JSON.parse(line)
  p state
  direction = %w(up down left right stay).sample
  response = {
    direction: direction,
    beat: state['beat'],
  }
  p response
  s.puts response.to_json
end

s.close
