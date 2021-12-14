require "colorize"
color_map = ColorMap.new "color_data.json"

def make_ord(number : Number) : String
  if number > 10 && number.to_s[-2] == '1'
    return "#{number}th"
  end

  number.to_s +
    case number.to_s[-1]
    when '1'
      "st"
    when '2'
      "nd"
    when '3'
      "rd"
    else
      "th"
    end
end

def make_newlines(input : String) : String
  line_break_regex = /(?<!\r)\n/
  result = input
  regex_match = input.match(line_break_regex)
  while regex_match
    result = result.sub(line_break_regex, "\r\n")
    regex_match = result.match(line_break_regex)
  end
  return result
end

class Colorizer
  property color_map : ColorMap
  property current_game : Hash(String, JSON::Any)

  def initialize(@color_map, @current_game = Hash(String, JSON::Any).new)
  end

  def colorize_string_for_team(
    away? : Bool,
    string : String
  ) : String
    string
      .colorize
      .bold
      .fore(@color_map.get_hex_color @current_game[away? ? "awayTeamColor" : "homeTeamColor"].as_s)
      .to_s
  end
end

colorizer = Colorizer.new color_map

abstract class Layout
  abstract def clear_last
end

class DefaultLayout < Layout
  property last_message : String = ""
  property last_league : Hash(String, JSON::Any) = Hash(String, JSON::Any).new
  property colorizer : Colorizer
  property feed_season_list : Hash(String, JSON::Any)

  def initialize(@colorizer, @feed_season_list)
  end

  def render(message : SourceData)
    message.leagues.try do |leagues|
      @last_league = leagues
    end

    if message.games.nil? || message.sim.nil?
      return @last_message
    end

    @last_message = String.build do |m|
      m << "\x1b7"          # bell
      m << "\x1b[1A\x1b[1J" # move cursor up one, clear from cursor to beginning of screen.
      m << "\x1b[1;1H"      # move cursor to top left of screen
      m << "\x1b[0J"        # clear from cursor to end of screen

      sim = message.sim.not_nil!
      readable_day = sim["day"].as_i + 1

      m << %(Day #{readable_day}, Season #{sim["season"].as_i + 1}).colorize.bold.to_s
      m << "\n\r"
      m << render_season_identifier @colorizer, message

      if message.games == 0
        m << "No games for day #{readable_day}"
      else
        message.games.not_nil!.sort_by { |g| get_team_name g, true }.each do |game|
          colorizer.current_game = game.as_h
          m << render_game colorizer, game
        end
      end

      m << "\x1b8"
    end

    @last_message
  end

  def get_team_name(
    game : JSON::Any,
    away : Bool
  ) : String
    get_team_identifier game, away, "awayTeamName", "homeTeamName", "fullName"
  end

  def get_team_nickname(
    game : JSON::Any,
    away : Bool
  ) : String
    get_team_identifier game, away, "awayTeamNickname", "homeTeamNickname", "nickname"
  end

  def get_team_identifier(
    game : JSON::Any,
    away : Bool,
    away_game_identifier : String,
    home_game_identifier : String,
    identifier : String
  ) : String
    if @last_league.has_key? "teams"
      target_team_id = away ? game["awayTeam"] : game["homeTeam"]
      last_league["teams"].as_a.each do |team_json|
        team = team_json.as_h
        if team["id"] == target_team_id
          team_name = team[identifier].to_s
          if team.has_key? "state"
            team_state = team["state"].as_h
            if team_state.has_key? "scattered"
              team_name = team_state["scattered"].as_h[identifier].to_s
            end
          end
          return team_name
        end
      end
      raise "Team with id #{target_team_id} not found in sim league object"
    else
      return away ? game[away_game_identifier].to_s : game[home_game_identifier].to_s
    end
  end

  def render_game(
    colorizer : Colorizer,
    game : JSON::Any
  ) : String
    away_team_name = get_team_name(game, true)
    home_team_name = get_team_name(game, false)
    away_team_nickname = get_team_nickname(game, true)
    home_team_nickname = get_team_nickname(game, false)
    String.build do |m|
      m << "\n\r"
      m << %(#{colorizer.colorize_string_for_team true, away_team_name})
      m << %( #{"@".colorize.underline} )
      m << %(#{colorizer.colorize_string_for_team false, home_team_name})
      m << %{ (#{colorizer.colorize_string_for_team true, game["awayScore"].to_s} v #{colorizer.colorize_string_for_team false, game["homeScore"].to_s})}
      m << "\n\r"
      m << %(#{game["topOfInning"].as_bool ? "Top of the" : "Bottom of the"} #{make_ord game["inning"].as_i + 1}).colorize.bold

      if game["topOfInning"].as_bool
        m << %( - #{colorizer.colorize_string_for_team false, game["homePitcherName"].to_s} pitching)
      else
        m << %( - #{colorizer.colorize_string_for_team true, game["awayPitcherName"].to_s} pitching)
      end

      m << "\n\r"

      if game["finalized"].as_bool?
        away_score = (game["awayScore"].as_f? || game["awayScore"].as_i?).not_nil!
        home_score = (game["homeScore"].as_f? || game["homeScore"].as_i?).not_nil!
        if away_score > home_score
          m << %(The #{colorizer.colorize_string_for_team true, away_team_nickname} #{"won against".colorize.underline} the #{colorizer.colorize_string_for_team false, home_team_nickname})
        else
          m << %(The #{colorizer.colorize_string_for_team false, home_team_nickname} #{"won against".colorize.underline} the #{colorizer.colorize_string_for_team true, away_team_nickname})
        end
        m << "\n\r"
      else
        if game["topOfInning"].as_bool?
          max_balls = game["awayBalls"].as_i?
          max_strikes = game["awayStrikes"].as_i?
          max_outs = game["awayOuts"].as_i?
          number_of_bases_including_home = game["awayBases"].as_i?
        else
          max_balls = game["homeBalls"].as_i?
          max_strikes = game["homeStrikes"].as_i?
          max_outs = game["awayOuts"].as_i?
          number_of_bases_including_home = game["homeBases"].as_i?
        end

        m << game["atBatBalls"]
        if max_balls && max_balls != 4
          m << %( (of #{max_balls}))
        end

        m << "-"

        m << game["atBatStrikes"]
        if max_strikes && max_strikes != 3
          m << %( (of #{max_strikes}))
        end

        bases_occupied = game["basesOccupied"].as_a
        if bases_occupied.size == 0
          m << ". Nobody on"
        else
          bases_occupied = bases_occupied.map { |b| b.as_i }
          m << ". #{bases_occupied.size} on ("

          number_bases = bases_occupied.max
          if number_of_bases_including_home && number_bases < number_of_bases_including_home
            number_bases = number_of_bases_including_home
          end
          if number_bases < 4
            number_bases = 4
          end

          bases = Array.new(number_bases - 1, 0)
          bases_occupied.each do |b|
            bases[b] += 1
          end

          bases.reverse.each do |b|
            if b == 0
              m << "\u{25cb}"
            elsif b == 1
              m << "\u{25cf}"
            else
              m << b.to_s
            end
          end

          m << ")"
        end

        number_of_outs = game["halfInningOuts"]
        if number_of_outs == 0
          m << ", no outs"
        elsif number_of_outs == 1
          m << ", 1 out"
        else
          m << ", #{number_of_outs} outs"
        end

        if max_outs && max_outs != 3
          m << %( (of #{max_outs}))
        end
        m << ".\r\n"

        m << make_newlines(game["lastUpdate"].as_s)
      end
    end
  end

  def render_season_identifier(
    colorizer : Colorizer,
    message : SourceData
  ) : String
    sim = message.sim.not_nil!
    id = sim["id"].to_s

    if id != "thisidisstaticyo"
      collection = @feed_season_list["items"][0]["data"]["collection"].as_a.index_by { |s| s["sim"] }
      return %(#{collection[id]["name"]}\r\n)
    else
      era_title = sim["eraTitle"].to_s
      sub_era_title = sim["subEraTitle"].to_s
      era_color = colorizer.color_map.get_hex_color sim["eraColor"].to_s
      sub_era_color = colorizer.color_map.get_hex_color sim["subEraColor"].to_s

      if !era_title.blank? && !sub_era_title.blank?
        return %(#{era_title.to_s.colorize.fore(era_color)} - #{sub_era_title.to_s.colorize.fore(sub_era_color)}\r\n).colorize.underline.to_s
      else
        return ""
      end
    end
  end

  def render_temporal(
    colorizer : Colorizer,
    temporal : Hash(String, JSON::Any)
  ) : String
    # alpha: number = number of peanuts that can be purchased
    # beta: number = squirrel count
    # gamma: number = entity id
    # delta: boolean = sponsor in store?
    # epsilon: boolean = is site takeover in process
    # zeta: string = actual output text

    if temporal.has_key? "doc"
      entity : Int32 = temporal["doc"]["gamma"].as_i
      zeta : String = make_newlines temporal["doc"]["zeta"].as_s
      if !zeta.blank?
        if @entities.entities_40.has_key? entity
          return "#{@entities.entities_40[entity]}#{zeta}"
        end
        return "#{@entities.entities_40[-1]}#{zeta}"
      end
    end
    return ""
  end

  def is_takeover_in_process : Bool
    if @last_temporal.has_key? "doc"
      if @last_temporal["doc"]["epsilon"]?
        return @last_temporal["doc"]["epsilon"].as_bool
      end
    end
    return false
  end

  def render_temporal_alert(
    message : String
  ) : String
    if message.starts_with? "Please Wait."
      return message[..1] << ".".mode(:blink)
    end
    return message
  end

  def clear_last : Nil
    @last_message = "\x1b7\x1b[1A\x1b[1J\x1b[1;1H\rloading..\x1b8"
  end
end
