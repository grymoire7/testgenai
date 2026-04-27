module Testgenai
  class Reporter
    def scan_results(methods)
      if methods.empty?
        puts "No untested methods found."
        return
      end
      puts "Found #{methods.size} untested method(s):"
      methods.each do |m|
        puts "  #{m[:class]}##{m[:method]}  #{m[:file]}:#{m[:start_line]}-#{m[:end_line]}"
      end
    end

    def context_result(method_info, context)
      puts "=== Context for #{method_info[:class]}##{method_info[:method]} ==="
      puts "  File: #{method_info[:file]}"
      unless context[:dependencies].to_a.empty?
        puts "  Dependencies:"
        context[:dependencies].each { |d| puts "    #{d}" }
      end
      unless context[:example_usage].to_a.empty?
        puts "  Example usages found: #{context[:example_usage].size}"
      end
      puts "  Related tests: #{context[:related_tests] ? "yes" : "none"}"
      puts
    end

    def success(method_info, result)
      puts "  ✓ #{method_info[:class]}##{method_info[:method]} → #{result[:output_path]} (#{result[:attempts]} attempt(s))"
    end

    def failure(method_info, result)
      puts "  ✗ #{method_info[:class]}##{method_info[:method]} failed after #{result[:attempts]} attempt(s)"
    end

    def skipped(method_info, error)
      puts "  - #{method_info[:class]}##{method_info[:method]} skipped: #{error.message}"
    end

    def summary(results)
      puts "\nSummary: #{results[:successful].size} generated, " \
           "#{results[:failed].size} failed, #{results[:skipped].size} skipped"
    end

    def fatal_error(error)
      puts "Fatal error: #{error.message}"
    end
  end
end
