# coding: utf-8
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

      player = nil
      @lock.synchronize do
        puts "Adding player #{name}"
        player = Player.new(
          name: name,
          socket: socket,
          position: @state.free_position
        )
        @state.add_player(player)
      end

      loop do
        move_str = socket.gets

        if move_str.nil? # disconnected
          @lock.synchronize do
            @state.remove_player(player)
          end
          socket.close
          return
        end

        move = JSON.parse(move_str)

        @lock.synchronize do
          player.set_move(move)
        end
      end
    end

    def on_disconnect(socket)
      socket.close
    end

    def get_name(socket)
      socket.puts 'To get started, please send me your name (a string followed by a new line character). We will send you the game state as JSON on one line and you have to send us your move as JSON on one line like this: {"direction": "up", "beat": 21} (directions are up, down, left, right, and stay)'
      socket.gets.chomp
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
      init_font
      init_tiles
      init_song
      init_sprites
      init_sounds
      init_server
    end

    private

    COLOR_BEATS = [
      0xff_000080,
      0xff_400080
    ].freeze
    COLOR_BLACK = 0xff_000000

    LAYER_BG = 0
    LAYER_SPRITES = 1

    MUSIC_DIR = __dir__ + '/music/'
    SPRITES_DIR = __dir__ + '/sprites/'
    SOUNDS_DIR = __dir__ + '/sounds/'

    POINTS_FOR_MONSTER_WIN = 1
    POINTS_FOR_MONSTER_LOSS = 1
    POINTS_FOR_PVP_WIN = 2
    POINTS_FOR_PVP_LOSS = -2
    POINTS_FOR_STAIRS = 3

    def init_state
      @state = State.new(
        on_collision: -> (actor:, target:) {
          case [actor.class, target.class]
          when [Player, Player] # pvp
            puts "#{actor.name} attacked #{target.name}"
            actor.score += POINTS_FOR_PVP_WIN
            target.score += POINTS_FOR_PVP_LOSS
            @sounds['hit'].play
          when [Player, Monster] # player killed a monster
            puts "#{actor.name} attacked a monster"
            actor.score += POINTS_FOR_MONSTER_WIN
            target.set_position(@state.free_position)
            @sounds['coin'].play
          when [Monster, Player] # monster killed a player
            puts "#{target.name} was attacked by a monster"
            target.score += POINTS_FOR_MONSTER_LOSS
            #target.set_position(free_position)
            @sounds['hit'].play
          when [Player, Stairs] # player gets points, stairs move
            puts "#{actor.name} found the stairs"
            actor.score += POINTS_FOR_STAIRS
            target.set_position(@state.free_position)
            @sounds['stairs'].play
          end
        }
      )
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
      paths = Dir.glob(SPRITES_DIR + name + '*.png')
      paths.map { |path| Gosu::Image.new(path) }
    end

    def load_sound_by_name(name)
      path = SOUNDS_DIR + name + '.wav'
      Gosu::Sample.new(path)
    end

    def init_sprites
      @sprites = {}
      %w(player zombie stairs).each do |name|
        @sprites[name] = load_sprite_by_name(name)
      end
    end

    def init_sounds
      @sounds = {}
      %w(coin hit stairs).each do |name|
        @sounds[name] = load_sound_by_name(name)
      end
    end

    def init_song
      @t0 = Time.now.to_f
      @song_name = ARGV.shift || 'track1'
      @song = Gosu::Song.new(self, MUSIC_DIR + @song_name + '.ogg')
      @song_info = YAML.load_file(MUSIC_DIR + @song_name + '.yml')
      @advance_every_n_beats = (ARGV.shift || 1).to_f
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
        draw_sprite_intention(player.x, player.y, intention: player.intention)
        draw_sprite_label(player.x, player.y, label: player.name + " (#{player.score})")
      end
    end

    def draw_sprite_intention(x, y, intention:)
      # TODO: rewrite all this, it's kind of awful
      w = @font.text_width('W')
      iw = @font.text_width(intention)
      h = @font.height
      big_r = w + 5
      small_r = big_r/3
      lx = x * @tile_size + (@tile_size - iw)
      ly = y * @tile_size + h
      draw_circle(lx, ly, w, 0, 0xff_ffffff)
      draw_circle(lx - 20, ly + 15, w/3, 0, 0xff_ffffff)
      @font.draw(intention, lx - iw/2, ly - h/2, LAYER_SPRITES + 1, 1, 1, 0xff_000000)
    end

    def draw_sprite_label(x, y, label:)
      lx = x * @tile_size + (@tile_size - @font.text_width(label)) / 2
      ly = (y + 1) * @tile_size - @font.height
      @font.draw(label, lx, ly, LAYER_SPRITES)
    end

    def draw_monsters
      sprite = @sprites['zombie'][@state.beat % 2]
      @state.monsters.each do |monster|
        draw_sprite_on_tile(sprite, monster.x, monster.y)
        draw_sprite_intention(monster.x, monster.y, intention: monster.intention)
      end
    end

    def draw_stairs
      sprite = @sprites['stairs'][@state.beat % 2]
      @state.stairs.each do |stairs|
        draw_sprite_on_tile(sprite, stairs.x, stairs.y)
      end
    end

    def draw_sprite_on_tile(img, x, y)
      cx = x * @tile_size + (@tile_size / 2 - img.width / 2)
      cy = y * @tile_size + (@tile_size / 2 - img.height / 2)
      img.draw(cx, cy, LAYER_SPRITES)
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
          game_object.do_move(@state)
        end
        @state.advance
        decide_monster_moves
        send_state_to_players
      end
    end

    def send_state_to_players
      @state.players.each do |player|
        player.send_state(@state)
      end
    end

    def decide_monster_moves
      @state.monsters.each do |monster|
        monster.decide_move(@state)
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
    DIRECTION_INTENTIONS = {
      'up' => '⬆',
      'down' => '⬇',
      'left' => '⬅',
      'right' => '➡',
      'stay' => ' ',
    }
    DIRECTION_INTENTIONS.default = '?'

    DIRECTION_DELTAS = {
      'up' => [0, -1],
      'down' => [0, +1],
      'left' => [-1, 0],
      'right' => [+1, 0],
    }
    DIRECTION_DELTAS.default = [0, 0]

    attr_reader :x, :y

    def initialize(position:)
      @x = position[0]
      @y = position[1]
      @move = nil
    end

    def to_json(opts = {})
      { x: x, y: y }.to_json(opts)
    end

    def set_move(move)
      @move = move
    end

    def do_move(state)
      # consume @move and update position
      return if @move.nil?
      begin
        if @move['beat'] != state.beat
          puts "This move is for beat #{@move['beat']} not #{state.beat}, too slow?"
          return
        end
        direction = @move['direction']
        delta = DIRECTION_DELTAS[direction]
        move_by(state, delta[0], delta[1])
      rescue RuntimeError => e
        puts e
        # it's okay, stand still
      end
      @move = nil
    end

    def at?(x, y)
      @x == x && @y == y
    end

    def set_position(position)
      @x = position[0]
      @y = position[1]
    end

    def move_by(state, dx, dy)
      new_x = @x + dx
      new_y = @y + dy
      if !state.on_board?(new_x, new_y)
        return
      end
      if new_x != x || new_y != y
        obj = state.game_object_at(new_x, new_y)
        if obj
          state.on_collision(actor: self, target: obj)
          return
        end
      end
      @x = new_x
      @y = new_y
    end

    def intention
      dir = @move && @move['direction']
      DIRECTION_INTENTIONS[dir]
    end
  end

  class Stairs < GameObject
  end

  class Player < GameObject
    attr_reader :name
    attr_reader :socket
    attr_accessor :score

    def initialize(name:, position:, socket:)
      super(position: position)
      @name = name
      @socket = socket
      @score = 0
    end

    def send_state(state)
      socket.puts(state.to_json)
    end

    def to_json(opts = {})
      { name: name, x: x, y: y }.to_json(opts)
    end
  end

  class Monster < GameObject
    def decide_move(state)
      @move = case state.beat % 2
              when 0 then { 'direction' => 'up', 'beat' => state.beat }
              when 1 then { 'direction' => 'down', 'beat' => state.beat }
              end
    end
  end

  # Game state that can be sent to clients
  class State
    attr_reader :width
    attr_reader :height
    attr_reader :beat
    attr_reader :players
    attr_reader :monsters
    attr_reader :stairs

    def initialize(on_collision: -> {})
      @on_collision = on_collision
      @width = 8
      @height = 6
      @beat = 0
      @players = []
      @monsters = []
      @stairs = []
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

    def on_collision(actor:, target:)
      @on_collision.call(actor: actor, target: target)
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
  end

  def self.start
    window = Danza::Window.new
    window.show
  end
end

Danza.start
