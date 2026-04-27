require "parser/current"

module Testgenai
  class CodeExtractor
    def self.extract(response)
      if (match = response.match(/```ruby\n(.*?)```/m))
        match[1]
      elsif (match = response.match(/```\n?(.*?)```/m))
        match[1]
      else
        response
      end
    end

    def self.valid_ruby?(code)
      Parser::CurrentRuby.parse(code)
      true
    rescue Parser::SyntaxError
      false
    end
  end
end
