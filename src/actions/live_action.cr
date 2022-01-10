require "socket"
require "colorize"
require "http/client"
require "../client.cr"
require "./base.cr"

class LiveAction < Action
  getter aliases : Set(String) = Set{"live"}

  def invoke(
    client : Client,
    tx : Channel({String, SourceData}),
    sources : Hash(String, Source),
    line : String
  ) : Nil
    client.writeable = true

    if client.source != "live"
      sources[client.source].rm_client
      sources["live"].add_client

      client.socket << "\x1b[1;1H"
      client.socket << "\x1b[0J"
      client.socket << "writing the present...".colorize.red.bold
      client.socket << "\x1b[10000B"
      client.socket << "\r"

      client.source = "live"
      client.renderer.clear_last
    end
  end
end
