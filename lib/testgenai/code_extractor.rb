require "parser/current"

module Testgenai
  class CodeExtractor
    def self.extract(response)
      if (match = response.match(/```ruby\n(.*?)```/m))
        match[1]
      elsif (match = response.match(/```\w*\n(.*?)```/m))
        match[1]
      else
        response
      end
    end

    def self.valid_ruby?(code)
      require "stringio"
      old_stderr = $stderr
      $stderr = StringIO.new
      Parser::CurrentRuby.parse(code)
      true
    rescue Parser::SyntaxError
      false
    ensure
      $stderr = old_stderr
    end
  end
end
