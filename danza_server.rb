require 'gosu'
require './gosu_ext'
require 'yaml'
require 'json'
require 'socket'
require 'monitor'

module Danza
  class Server
    def initialize(state)
      @state = state
      @lock = Monitor.new
    end

    def on_connect(state, socket)
      puts 'Connection detected'
      name = get_name(socket)
      puts "Client connected: #{name}"

      if @state.players.find { |player| player.name == name }
        puts 'That name is already taken'
        socket.puts 'That name is already taken'
        socket.close
        return
      end

      #@lock.synchronize do
        puts "Adding player #{name}"
        p @state.free_position
        new_player = Player.new(
          name: name,
          socket: socket,
          position: @state.free_position
        )
        puts "Created new player"
        @state.add_player(new_player)
      #end

      loop do
        move = socket.gets

        if move.nil? # disconnected
          @lock.synchronize do
            player = @state.players.find { |player| player.socket == socket }
            @state.remove_player(player)
          end
          socket.close
          return
        end

        @lock.synchronize do
          @state.set_move(player: player, move: move)
        end
      end
    end

    def on_disconnect(socket)
      socket.close
    end

    def get_name(socket)
      socket.puts 'To get started, please send me your name (a string followed by a new line character)'
      socket.gets
    end

    def start
      @server_thread = Thread.start do
        Thread.current.abort_on_exception = true
        @server = TCPServer.new 8787
        puts 'Server listening on 8787'
        loop do
          Thread.start(@server.accept, @state) do |socket, state|
            Thread.current.abort_on_exception = true
            on_connect(state, socket)
          end
        end
      end
    end
  end

  class Window < Gosu::Window
    include GosuExt

    def initialize(fullscreen: false)
      super 1024, 768, fullscreen
      self.caption = 'Danza'
      init_state
      init_tiles
      init_song
      init_sprites
      init_server
    end

    private

    COLOR_BEATS = [
      0xc0_0000ff,
      0xff_ff0000
    ].freeze
    COLOR_BLACK = 0xff_000000

    LAYER_BG = 0
    LAYER_PLAYERS = 1

    def init_state
      @state = State.new
    end

    def init_font
      @font = Gosu::Font.new(20)
    end

    def init_tiles
      @tile_size = 128
    end

    def init_server
      @server = Server.new(@state)
      @server.start
    end

    def load_sprite_by_name(name)
      paths = Dir.glob(__dir__ + '/' + name + '*.png')
      paths.map { |path| Gosu::Image.new(path) }
    end

    def init_sprites
      @sprites = {}
      %w(player zombie stairs).each do |name|
        @sprites[name] = load_sprite_by_name(name)
      end
    end

    def init_song
      @t0 = Time.now.to_f
      @song_name = 'music'
      @song = Gosu::Song.new(self, @song_name + '.ogg')
      @song_info = YAML.load_file(@song_name + '.yml')
      @advance_every_n_beats = 1
      @bpm = @song_info['bpm'].to_f / @advance_every_n_beats
      @interval = 60.0 / @bpm
      @song.play
    end

    def draw
      draw_tiles
      draw_players
      draw_monsters
      draw_stairs
    end

    def color_tile?(x, y)
      ((x + y) % 2) == (@state.beat % 2)
    end

    def tile_color
      COLOR_BEATS[@state.beat % COLOR_BEATS.size]
    end

    def draw_tiles
      color = tile_color
      @state.positions.each do |x, y|
        next if color_tile?(x, y)
        draw_rect(
          x * @tile_size,
          y * @tile_size,
          @tile_size - 1,
          @tile_size - 1,
          color,
          LAYER_BG
        )
      end
    end

    def draw_players
      sprite = @sprites['player'][@state.beat % 2]
      @state.players.each do |player|
        draw_sprite_on_tile(sprite, player.x, player.y)
      end
    end

    def draw_monsters
      sprite = @sprites['zombie'][@state.beat % 2]
      @state.monsters.each do |monster|
        draw_sprite_on_tile(sprite, monster.x, monster.y)
      end
    end

    def draw_stairs
      sprite = @sprites['stairs'][0]
      @state.stairs.each do |stairs|
        draw_sprite_on_tile(sprite, stairs.x, stairs.y)
      end
    end

    def draw_sprite_on_tile(img, x, y)
      cx = x * @tile_size + (@tile_size / 2 - img.width / 2)
      cy = y * @tile_size + (@tile_size / 2 - img.height / 2)
      img.draw(cx, cy, LAYER_PLAYERS)
    end

    def game_objects
      @state.players + @state.monsters
    end

    def at_most_every_interval
      return if Time.now.to_f < (@t0 + @interval)
      @t0 = Time.now.to_f
      yield
    end

    def update
      at_most_every_interval do
        game_objects.each do |game_object|
          game_object.move(@state)
        end
        @state.advance
      end
    end

    def button_down(id)
      case id
      when Gosu::Button::KbEscape, char_to_button_id('q')
        close
      end
    end
  end

  class GameObject
    attr_reader :x, :y

    def initialize(position:)
      @x = position[0]
      @y = position[1]
    end

    def move(state)
      # no-op
    end

    def at?(x, y)
      @x == x && @y == y
    end
  end

  class Stairs < GameObject
    def to_json(opts = {})
      { type: 'stairs', x: x, y: y }.to_json(opts)
    end
  end

  class Player < GameObject
    attr_reader :name
    attr_reader :socket

    def initialize(name:, position:, socket:)
      super(position: position)
      @name = name
      @socket = socket
    end

    def move(state)
      # TODO: call function supplied by client
    end

    def to_json(opts = {})
      { type: 'player', name: name, x: x, y: y }.to_json(opts)
    end
  end

  class Monster < GameObject
    def move(state)
      diff = (state.beat % 2) * 2 - 1 # -1 or +1 based on beat
      new_y = y + diff
      if !state.on_board?(x, new_y) || state.game_object_is?(x, new_y, Monster)
        return
      end
      @y = new_y
    end

    def to_json(opts = {})
      { type: 'monster', x: x, y: y }.to_json(opts)
    end
  end

  # Game state that can be marshalled and sent to clients
  class State
    attr_reader :width
    attr_reader :height
    attr_reader :beat
    attr_reader :players
    attr_reader :monsters
    attr_reader :stairs

    def initialize
      @width = 8
      @height = 6
      @beat = 0
      @players = []
      @monsters = []
      @stairs = []
      # @players = [
      #   Player.new(name: 'Alice', position: free_position),
      #   Player.new(name: 'Bob', position: free_position),
      # ]
      @monsters = Array.new(3) { Monster.new(position: free_position) }
      @stairs = Array.new(1) { Stairs.new(position: free_position) }
    end

    def remove_player(player)
      @players.delete(player)
    end

    def add_player(player)
      @players << player
    end

    def positions
      Enumerator.new do |e|
        @height.times do |y|
          @width.times do |x|
            e << [x, y]
          end
        end
      end
    end

    def game_objects
      @players + @monsters + @stairs
    end

    def game_object_at(x, y)
      game_objects.find { |a| a.at?(x, y) }
    end

    def game_object_is?(x, y, type)
      game_object_at(x, y).is_a?(type)
    end

    def randomised_positions
      positions.to_a.shuffle
    end

    def free_position
      (randomised_positions - game_objects.map { |o| [o.x, o.y] }).first
    end

    def advance
      @beat += 1
      detect_collisions
    end

    def on_board?(x, y)
      x >= 0 &&
        x < @width &&
        y >= 0 &&
        y < @height
    end

    def to_json(opts = {})
      {
        width: @width,
        height: @height,
        beat: @beat,
        players: @players,
        monsters: @monsters,
        stairs: @stairs,
      }.to_json(opts)
    end

    def detect_collisions
      # TODO
    end
  end

  def self.start
    window = Danza::Window.new
    window.show
  end
end

Danza.start
