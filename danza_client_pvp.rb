require 'socket'
require 'json'

s = TCPSocket.new 'localhost', 8787
instructions = s.gets
puts 'CLIENT INSTRUCTIONS:'
puts instructions
puts
name = ARGV[0] || 'Hunta'
s.puts name

loop do
  line = s.gets
  break if line.nil?
  state = JSON.parse(line)
  player = state['players'].find { |p| p['name'] == name }
  target = state['players'].find { |p| p['name'] != name }
  if target.nil? or player.nil?
    next
  end
  if player['x'] < target['x']
    direction = 'right'
  elsif player['x'] > target['x']
    direction = 'left'
  elsif player['y'] > target['y']
    direction = 'up'
  elsif player['y'] < target['y']
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
