require 'drb'
require 'gosu'
require 'yaml'
require './gosu_ext'

module Danza

  class Actor
    attr_reader :x, :y

    def initialize
      @x = 0
      @y = 0
    end

    def set_position(x, y)
      @x = x
      @y = y
    end
  end

  class Stairs < Actor
  end

  class Player < Actor
  end

  class Monster < Actor
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
      @players = [Player.new, Player.new]
      @players.each do |player|
        player.set_position(*positions.pop)
      end
      @monsters = [Monster.new, Monster.new]
      @monsters.each do |monster|
        monster.set_position(*positions.pop)
      end
      @stairs = Stairs.new
      @stairs.set_position(*positions.pop)
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
    end
  end

  # Top level window
  class Window < Gosu::Window
    include GosuExt

    def initialize
      super 1024, 768, fullscreen = false
      self.caption = 'Danza'
      init_state
      init_tiles
      init_song
      init_sprites
    end

    private

    COL_NO = 0xc0_ff0000
    COL_YES = 0xff_00ff00
    COL_HL = 0xff_ffffff
    COL_NORMAL = 0x50_ffffff
    COL_LETTER = 0xff_ffff00
    COL_BLACK = 0xff_000000

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

    def load_sprite_by_name(name)
      paths = Dir.glob(__dir__ + '/' + name + '*.png')
      paths.map { |path| Gosu::Image.new(path) }
    end

    def init_sprites
      @sprites = {}
      @sprites['player'] = load_sprite_by_name('player')
      @sprites['zombie'] = load_sprite_by_name('zombie')
      @sprites['stairs'] = load_sprite_by_name('stairs')
    end

    def init_song
      @t0 = Time.now.to_f
      @song_name = 'music'
      @song = Gosu::Song.new(self, @song_name + '.ogg')
      @song_info = YAML.load_file(@song_name + '.yml')
      @bpm = @song_info['bpm'] / 1.0
      @interval = 60.0 / @bpm
      @song.play
    end

    def draw
      draw_tiles
      draw_players
      draw_monsters
      draw_stairs
    end

    def draw_tiles
      col = @state.beat.even? ? COL_YES : COL_NO
      @state.height.times do |y|
        @state.width.times do |x|
          if ((x + y) % 2) == (@state.beat % 2)
            next
          end
          draw_rect(
            x * @tile_size,
            y * @tile_size,
            @tile_size - 1,
            @tile_size - 1,
            col,
            LAYER_BG
          )
        end
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
      stairs = @state.stairs
      sprite = @sprites['stairs'][0]
      draw_sprite_on_tile(sprite, stairs.x, stairs.y)
    end

    def draw_sprite_on_tile(img, x, y)
      cx = x * @tile_size + (@tile_size / 2 - img.width / 2)
      cy = y * @tile_size + (@tile_size / 2 - img.height / 2)
      img.draw(cx, cy, LAYER_PLAYERS)
    end

    def update
      if Time.now.to_f > (@t0 + @interval)
        @t0 = Time.now.to_f
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

  # listen address
  URI = 'druby://localhost:8787'.freeze

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

  def self.start_game_server
    server = Danza::Server.new
    DRb.start_service(Danza::URI, server)
  end

  def self.open_window
    window = Danza::Window.new


    $SAFE = 1 # DRb recommendation

    window.show
  end

  def self.start
    start_game_server
    open_window
    #DRb.thread.join
  end
end

Danza.start

