require 'socket'
require 'json'

s = TCPSocket.new 'localhost', 8787
instructions = s.gets
puts 'CLIENT INSTRUCTIONS:'
puts instructions
puts
name = ARGV[0] || 'Greedy'
s.puts name

loop do
  line = s.gets
  break if line.nil?
  state = JSON.parse(line)
  player = state['players'].find { |p| p['name'] == name }
  coins = state['coins'].first
  if player['x'] < coins['x']
    direction = 'right'
  elsif player['x'] > coins['x']
    direction = 'left'
  elsif player['y'] > coins['y']
    direction = 'up'
  elsif player['y'] < coins['y']
    direction = 'down'
  else
    next
  end
  response = {
    direction: direction,
    beat: state['beat'],
  }.to_json
  s.puts response
end

s.close
