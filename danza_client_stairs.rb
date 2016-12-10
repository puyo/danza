require 'socket'
require 'json'

s = TCPSocket.new 'localhost', 8787
instructions = s.gets
puts 'CLIENT INSTRUCTIONS:'
puts instructions
puts
name = ARGV[0] || 'Steppy'
s.puts name

loop do
  line = s.gets
  break if line.nil?
  state = JSON.parse(line)
  print state['beat'], ': '
  p state
  player = state['players'].find { |p| p['name'] == name }
  stairs = state['stairs'].first
  p player
  p stairs
  if player['x'] < stairs['x']
    direction = 'right'
  elsif player['x'] > stairs['x']
    direction = 'left'
  elsif player['y'] > stairs['y']
    direction = 'up'
  elsif player['y'] < stairs['y']
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
