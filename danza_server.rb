require 'drb'
require 'gosu'
require 'yaml'
require './gosu_ext'
require 'json'

module Danza
  URI = 'druby://localhost:8787'.freeze

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
      # $SAFE = 1 is a DRb recommendation, but must be done after loading assets
      # from file system
      $SAFE = 1
      @server = Danza::Server.new
      DRb.start_service(Danza::URI, @server)
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

    def each_tile
      @state.height.times do |y|
        @state.width.times do |x|
          yield x, y
        end
      end
    end

    def draw_tiles
      color = tile_color
      each_tile do |x, y|
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

    def actors
      @state.players + @state.monsters
    end

    def at_most_every_interval
      return if Time.now.to_f < (@t0 + @interval)
      @t0 = Time.now.to_f
      yield
    end

    def update
      at_most_every_interval do
        actors.each do |actor|
          actor.move(@state)
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
    # don't do anything
  end

  class Player < GameObject
    attr_reader :name

    def initialize(name:, position:)
      super(position: position)
      @name = name
    end

    def move(state)
      # TODO: call function supplied by client
    end
  end

  class Monster < GameObject
    def move(state)
      diff = (state.beat % 2) * 2 - 1 # -1 or +1 based on beat
      new_y = y + diff
      if !state.on_board?(x, new_y) || state.actor_is?(x, new_y, Monster)
        return
      end
      @y = new_y
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
      positions = randomised_positions
      @players = [
        Player.new(name: 'Alice', position: positions.pop),
        Player.new(name: 'Bob', position: positions.pop),
      ]
      @monsters = [
        Monster.new(position: positions.pop),
        Monster.new(position: positions.pop),
      ]
      @stairs = [
        Stairs.new(position: positions.pop)
      ]
    end

    def actor_at(x, y)
      (@players + @monsters + @stairs).find { |a| a.at?(x, y) }
    end

    def actor_is?(x, y, type)
      actor_at(x, y).is_a?(type)
    end

    def randomised_positions
      positions = []
      @height.times do |y|
        @width.times do |x|
          positions << [x, y]
        end
      end
      positions.shuffle!
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

    def to_client_json
      {
        width: @width,
        height: @height,
        beat: @beat,
        players: @players,
        monsters: @monsters,
        stairs: @stairs,
      }.to_json
    end

    def detect_collisions
      # TODO
    end
  end

  # Some thing
  class Server
    def initialize
      @actor_move_functions = {}
    end

    def set_actor_logic(name, &block)
      p actor: name
      @actor_move_functions[name] = block
    end

    def all_steps
      @actor_move_functions.values.each do |block|
        move = block.call({ input: 100 })
        p move: move
      end
    end
  end

  def self.start
    window = Danza::Window.new
    window.show
    # Commented because Gosu blocks and once we close the window, we're done
    # anyway so don't bother waiting
    #DRb.thread.join
  end
end

Danza.start
